# Shared safety helpers for maintenance scripts.

function Get-NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-PathInsideOrEqual {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Parent
    )

    $child = Get-NormalizedPath $Path
    $root = Get-NormalizedPath $Parent

    if ($child.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $child.StartsWith(
        $root + '\',
        [System.StringComparison]::OrdinalIgnoreCase
    )
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
        return
    }

    # External model libraries must be genuinely external. This prevents an
    # uninstall from ever deleting models through an owned runtime/cache tree.
    if ((Test-PathInsideOrEqual -Path $models -Parent $root) -or
        (Test-PathInsideOrEqual -Path $root -Parent $models)) {
        throw "ModelsRoot must be either '$defaultModels' or a non-overlapping external path. Refusing: $models"
    }
}

function Get-UnslothManagedProcesses {
    param([Parameter(Mandatory)][string]$InstallationRoot)

    $runtime = Get-NormalizedPath (Join-Path $InstallationRoot 'runtime')

    @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                if ($_.ProcessId -eq $PID) { return $false }

                $exe = [string]$_.ExecutablePath
                $cmd = [string]$_.CommandLine

                ($exe -and (Test-PathInsideOrEqual -Path $exe -Parent $runtime)) -or
                ($cmd -and $cmd.IndexOf($runtime, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            } |
            Select-Object ProcessId, Name, ExecutablePath, CommandLine
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
