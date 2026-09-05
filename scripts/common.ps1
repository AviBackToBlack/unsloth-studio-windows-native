# Shared safety helpers for maintenance scripts.

if (-not ('UnslothStudioWindowsNative.NativePath' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace UnslothStudioWindowsNative {
    public static class NativePath {
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint FILE_SHARE_DELETE = 0x00000004;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        private const uint VOLUME_NAME_DOS = 0x0;
        private const uint VOLUME_NAME_GUID = 0x1;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile
        );

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandle(
            SafeFileHandle hFile,
            StringBuilder lpszFilePath,
            uint cchFilePath,
            uint dwFlags
        );

        private static string GetFinalPathWithFlags(SafeFileHandle handle, uint flags) {
            var buffer = new StringBuilder(32768);
            uint result = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, flags);
            if (result == 0) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            if (result >= buffer.Capacity) {
                buffer = new StringBuilder((int)result + 1);
                result = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, flags);
                if (result == 0) {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
            }
            return buffer.ToString();
        }

        public static string GetFinalPath(string path) {
            using (SafeFileHandle handle = CreateFile(
                path,
                0,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS,
                IntPtr.Zero
            )) {
                if (handle.IsInvalid) {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }

                try {
                    return GetFinalPathWithFlags(handle, VOLUME_NAME_GUID);
                } catch (Win32Exception) {
                    return GetFinalPathWithFlags(handle, VOLUME_NAME_DOS);
                }
            }
        }
    }
}
'@
}

function Get-NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)

    $trimmed = $Path.Trim().Trim('"')
    if (-not [System.IO.Path]::IsPathFullyQualified($trimmed)) {
        throw "Path must be fully qualified: $Path"
    }

    return [System.IO.Path]::GetFullPath($trimmed).TrimEnd('\')
}

function Get-CanonicalExistingPath {
    param([Parameter(Mandatory)][string]$Path)

    $normalized = Get-NormalizedPath $Path
    if (-not (Test-Path -LiteralPath $normalized)) {
        throw "Cannot canonicalize a path that does not exist: $normalized"
    }

    return [UnslothStudioWindowsNative.NativePath]::GetFinalPath($normalized).TrimEnd('\')
}

function Test-PathInsideOrEqual {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Parent,
        [switch]$PhysicalWhenPossible
    )

    $child = Get-NormalizedPath $Path
    $root = Get-NormalizedPath $Parent

    if ($PhysicalWhenPossible -and
        (Test-Path -LiteralPath $child) -and
        (Test-Path -LiteralPath $root)) {
        $child = Get-CanonicalExistingPath $child
        $root = Get-CanonicalExistingPath $root
    }

    if ($child.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $child.StartsWith(
        $root + '\',
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Assert-ManagedChildPhysicalLocation {
    param(
        [Parameter(Mandatory)][string]$InstallationRoot,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $root = Get-NormalizedPath $InstallationRoot
    $pathNormalized = Get-NormalizedPath $Path
    $expectedLexical = Get-NormalizedPath (Join-Path $root $RelativePath)

    if (-not $pathNormalized.Equals($expectedLexical, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Managed path must use the expected location '$expectedLexical': $pathNormalized"
    }

    if ((Test-Path -LiteralPath $root) -and (Test-Path -LiteralPath $pathNormalized)) {
        $rootFinal = Get-CanonicalExistingPath $root
        $pathFinal = Get-CanonicalExistingPath $pathNormalized
        $expectedFinal = (Join-Path $rootFinal $RelativePath).TrimEnd('\')

        if (-not $pathFinal.Equals($expectedFinal, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Managed path resolves through a filesystem alias/junction outside its expected location '$expectedLexical': $pathFinal"
        }
    }
}

function Assert-SafeModelsRoot {
    param(
        [Parameter(Mandatory)][string]$InstallationRoot,
        [Parameter(Mandatory)][string]$ModelsRoot
    )

    $root = Get-NormalizedPath $InstallationRoot
    $models = Get-NormalizedPath $ModelsRoot
    $defaultModels = Get-NormalizedPath (Join-Path $root 'models')

    if ($models.Equals($defaultModels, [System.StringComparison]::OrdinalIgnoreCase)) {
        # The default spelling is allowed only when it physically resolves to
        # the real <root>\models directory, never a junction/alias elsewhere.
        Assert-ManagedChildPhysicalLocation `
            -InstallationRoot $root `
            -Path $models `
            -RelativePath 'models'
        return
    }

    if ((Test-PathInsideOrEqual -Path $models -Parent $root) -or
        (Test-PathInsideOrEqual -Path $root -Parent $models)) {
        throw "ModelsRoot must be either '$defaultModels' or a non-overlapping external path. Refusing: $models"
    }

    if ((Test-Path -LiteralPath $models) -and (Test-Path -LiteralPath $root)) {
        if ((Test-PathInsideOrEqual -Path $models -Parent $root -PhysicalWhenPossible) -or
            (Test-PathInsideOrEqual -Path $root -Parent $models -PhysicalWhenPossible)) {
            throw "ModelsRoot resolves through a filesystem alias/junction to overlap the installation root. Refusing: $models"
        }
    }
}

function Test-CommandLineReferencesRuntime {
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$RuntimePath
    )

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        return $false
    }

    $escaped = [regex]::Escape((Get-NormalizedPath $RuntimePath))
    $pattern = "(?i)(?:^|[\s`\"'])$escaped(?=$|[\\/\s`\"'])"
    return [regex]::IsMatch($CommandLine, $pattern)
}

function Get-UnslothManagedProcesses {
    param([Parameter(Mandatory)][string]$InstallationRoot)

    $runtime = Get-NormalizedPath (Join-Path $InstallationRoot 'runtime')

    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    } catch {
        throw "Could not enumerate Windows processes through CIM/WMI; managed-process ownership cannot be established safely. $($_.Exception.Message)"
    }

    @(
        $processes |
            Where-Object {
                if ($_.ProcessId -eq $PID) { return $false }

                $exe = [string]$_.ExecutablePath
                $cmd = [string]$_.CommandLine
                $exeManaged = $false

                if ($exe) {
                    try {
                        $exeManaged = Test-PathInsideOrEqual -Path $exe -Parent $runtime -PhysicalWhenPossible
                    } catch {
                        $exeManaged = $false
                    }
                }

                $exeManaged -or (Test-CommandLineReferencesRuntime -CommandLine $cmd -RuntimePath $runtime)
            } |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine
    )
}

function Assert-UnslothStopped {
    param([Parameter(Mandatory)][string]$InstallationRoot)

    $managed = @(Get-UnslothManagedProcesses -InstallationRoot $InstallationRoot)
    if ($managed.Count -eq 0) {
        return
    }

    $summary = ($managed | ForEach-Object { "PID $($_.ProcessId) $($_.Name)" }) -join ', '
    throw "Managed Unsloth processes are still running: $summary. Stop Studio before maintenance."
}
