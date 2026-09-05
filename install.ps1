[CmdletBinding()]
param(
    [string]$ModelsRoot,
    [switch]$Repair
)

$ErrorActionPreference = 'Stop'

$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$Pwsh = (Get-Process -Id $PID).Path

. "$Root\scripts\common.ps1"

if (-not $IsWindows) {
    throw 'This installer supports Windows only.'
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or newer is required. Run this script from pwsh.exe.'
}

if (-not [Environment]::Is64BitProcess) {
    throw 'Run the installer from 64-bit PowerShell.'
}

$InstallState = "$Root\forensic\install-state.json"
$RequiredRuntime = @(
    "$Root\runtime\unsloth_studio\Scripts\python.exe"
    "$Root\runtime\bin\unsloth.cmd"
    "$Root\runtime\llama.cpp\build\bin\Release\llama-server.exe"
)

$CompleteInstall = (
    (Test-Path -LiteralPath $InstallState -PathType Leaf) -and
    (@($RequiredRuntime | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0)
)

$PartialInstall = (
    (Test-Path -LiteralPath "$Root\runtime" -PathType Container) -or
    (Test-Path -LiteralPath "$Root\tools" -PathType Container) -or
    (Test-Path -LiteralPath "$Root\python" -PathType Container)
) -and -not $CompleteInstall

if ($CompleteInstall -and -not $Repair) {
    throw 'A complete installation already exists. Use .\update.ps1 for updates or .\install.ps1 -Repair to repair/revalidate it.'
}

if ($PartialInstall -and -not $Repair) {
    throw 'A partial installation was detected. Re-run with .\install.ps1 -Repair to resume/rebuild managed components safely.'
}

if ($Repair) {
    Assert-UnslothStopped -InstallationRoot $Root
    Write-Host "`n=== REPAIR MODE ===" -ForegroundColor Yellow
    Write-Host 'Existing managed files and Studio state will be preserved where possible.'
}

Write-Host "`n=== HOST PREREQUISITES ===" -ForegroundColor Cyan

$Git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue
if (-not $Git) {
    throw 'Git for Windows is required and was not found on PATH.'
}

$Nvidia = Get-Command nvidia-smi.exe -CommandType Application -ErrorAction SilentlyContinue
if (-not $Nvidia) {
    throw 'NVIDIA driver / nvidia-smi.exe is required and was not found.'
}

$LongPaths = (
    Get-ItemProperty `
        'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
        -Name LongPathsEnabled `
        -ErrorAction SilentlyContinue
).LongPathsEnabled

if ($LongPaths -ne 1) {
    throw 'Windows long path support is not enabled (LongPathsEnabled != 1). Enable it before installing.'
}

$VcRuntime = Get-ItemProperty `
    'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' `
    -ErrorAction SilentlyContinue

if (-not $VcRuntime -or $VcRuntime.Installed -ne 1) {
    throw 'Microsoft Visual C++ 2015-2022 Redistributable (x64) is required. Install it before running this installer.'
}

Write-Host "PowerShell : $($PSVersionTable.PSVersion)"
Write-Host "Git        : $(& $Git.Source --version)"
Write-Host "NVIDIA     : $((& $Nvidia.Source --query-gpu=name,driver_version,memory.total --format=csv,noheader) -join '; ')"
Write-Host 'Long paths : enabled'
Write-Host "VC++       : $($VcRuntime.Version)"

$ExistingConfigPath = "$Root\config.psd1"
$ExistingConfig = $null
if (Test-Path -LiteralPath $ExistingConfigPath -PathType Leaf) {
    $ExistingConfig = Import-PowerShellDataFile -LiteralPath $ExistingConfigPath
}

if ([string]::IsNullOrWhiteSpace($ModelsRoot)) {
    if ($ExistingConfig -and -not [string]::IsNullOrWhiteSpace($ExistingConfig.ModelsRoot)) {
        $ExistingModelsRoot = [string]$ExistingConfig.ModelsRoot
        if (-not [System.IO.Path]::IsPathFullyQualified($ExistingModelsRoot)) {
            throw "ModelsRoot in existing config.psd1 must be a fully qualified absolute path: $ExistingModelsRoot"
        }
        $ModelsRoot = [System.IO.Path]::GetFullPath($ExistingModelsRoot)
    } else {
        $ModelsRoot = Join-Path $Root 'models'
    }
} elseif (-not [System.IO.Path]::IsPathFullyQualified($ModelsRoot)) {
    throw '-ModelsRoot must be a fully qualified absolute path.'
} else {
    $ModelsRoot = [System.IO.Path]::GetFullPath($ModelsRoot)
}

Assert-SafeModelsRoot -InstallationRoot $Root -ModelsRoot $ModelsRoot

$ManagedTopLevel = [ordered]@{
    runtime = "$Root\runtime"
    tools = "$Root\tools"
    python = "$Root\python"
    cache = "$Root\cache"
    logs = "$Root\logs"
    forensic = "$Root\forensic"
    work = "$Root\work"
}

$Dirs = @(
    "$Root\runtime"
    "$Root\tools\uv"
    "$Root\python"
    "$Root\cache\uv"
    "$Root\cache\huggingface\hub"
    "$Root\cache\huggingface\xet"
    "$Root\cache\torch"
    "$Root\cache\pip"
    "$Root\cache\temp"
    "$Root\logs"
    "$Root\forensic\preinstall"
    "$Root\forensic\updates"
    "$Root\work"
    $ModelsRoot
)

foreach ($Dir in $Dirs) {
    [System.IO.Directory]::CreateDirectory($Dir) | Out-Null
}

# Every managed top-level directory must physically remain below this root.
# Junctions/reparse aliases to external locations defeat the containment model.
foreach ($Relative in $ManagedTopLevel.Keys) {
    Assert-ManagedChildPhysicalLocation `
        -InstallationRoot $Root `
        -Path $ManagedTopLevel[$Relative] `
        -RelativePath $Relative
}
Assert-SafeModelsRoot -InstallationRoot $Root -ModelsRoot $ModelsRoot

$escapedModelsRoot = $ModelsRoot.Replace("'", "''")
$Port = if ($ExistingConfig -and $null -ne $ExistingConfig.Port) { [int]$ExistingConfig.Port } else { 8888 }
@"
@{
    ModelsRoot = '$escapedModelsRoot'
    Port = $Port
}
"@ | Set-Content -LiteralPath $ExistingConfigPath -Encoding utf8

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Baseline = "$Root\forensic\preinstall\$Stamp"
[System.IO.Directory]::CreateDirectory($Baseline) | Out-Null

$UserPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
$MachinePathBefore = [Environment]::GetEnvironmentVariable('Path', 'Machine')

$KnownExternalPaths = [ordered]@{
    ProfileUnsloth = "$env:USERPROFILE\.unsloth"
    LocalAppDataUnsloth = "$env:LOCALAPPDATA\Unsloth Studio"
    RoamingAppDataUnsloth = "$env:APPDATA\Unsloth Studio"
}

$ExternalBefore = [ordered]@{}
foreach ($Name in $KnownExternalPaths.Keys) {
    $ExternalBefore[$Name] = Test-Path -LiteralPath $KnownExternalPaths[$Name]
}

[pscustomobject]@{
    Timestamp = (Get-Date).ToString('o')
    Mode = if ($Repair) { 'repair' } else { 'install' }
    Root = $Root
    ModelsRoot = $ModelsRoot
    UserPath = $UserPathBefore
    MachinePath = $MachinePathBefore
    CMake = (Get-Command cmake.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    NVCC = (Get-Command nvcc.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    Node = (Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    Python = (Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    ProfileUnsloth = $ExternalBefore.ProfileUnsloth
    LocalAppDataUnsloth = $ExternalBefore.LocalAppDataUnsloth
    RoamingAppDataUnsloth = $ExternalBefore.RoamingAppDataUnsloth
} | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath "$Baseline\baseline.json" -Encoding utf8

Write-Host "`nBaseline: $Baseline" -ForegroundColor DarkGray

. "$Root\scripts\env.ps1"

Write-Host "`n=== INSTALL / REFRESH UV ===" -ForegroundColor Cyan
$UvInstaller = "$Root\work\uv-install.ps1"
Invoke-WebRequest -Uri 'https://astral.sh/uv/install.ps1' -OutFile $UvInstaller -UseBasicParsing
$UvInstallerHash = (Get-FileHash -LiteralPath $UvInstaller -Algorithm SHA256).Hash
& $Pwsh -NoLogo -NoProfile -File $UvInstaller
if ($LASTEXITCODE -ne 0) {
    throw "uv installer failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $script:UnslothUv -PathType Leaf)) {
    throw "uv was not installed at the expected path: $script:UnslothUv"
}
& $script:UnslothUv --version

Write-Host "`n=== INSTALL / REFRESH PYTHON 3.13 ===" -ForegroundColor Cyan
Assert-ManagedChildPhysicalLocation -InstallationRoot $Root -Path "$Root\python" -RelativePath 'python'
& $script:UnslothUv python install 3.13 --no-bin --no-config
if ($LASTEXITCODE -ne 0) {
    throw "uv python install failed with exit code $LASTEXITCODE"
}

$ResolvedPython = (& $script:UnslothUv python find --managed-python 3.13).Trim()
if (-not $ResolvedPython -or -not (Test-Path -LiteralPath $ResolvedPython -PathType Leaf)) {
    throw 'Could not resolve the uv-managed Python 3.13 interpreter.'
}

$PythonRootExpected = [System.IO.Path]::GetFullPath("$Root\python").TrimEnd('\')
$PythonResolvedFull = [System.IO.Path]::GetFullPath($ResolvedPython)
Assert-ManagedChildPhysicalLocation -InstallationRoot $Root -Path $PythonRootExpected -RelativePath 'python'
if (-not (Test-PathInsideOrEqual -Path $PythonResolvedFull -Parent $PythonRootExpected -PhysicalWhenPossible)) {
    throw "Managed Python escaped the physical installation Python root: $PythonResolvedFull"
}

[ordered]@{
    recorded_at = (Get-Date).ToString('o')
    executable = $PythonResolvedFull
    version = (& $PythonResolvedFull --version 2>&1 | Out-String).Trim()
} | ConvertTo-Json -Depth 3 |
    Set-Content -LiteralPath "$Root\forensic\managed-python.json" -Encoding utf8

. "$Root\scripts\env.ps1"
& $ResolvedPython --version

Write-Host "`n=== INSTALL / REPAIR UNSLOTH STUDIO ===" -ForegroundColor Cyan
$Installer = "$Root\work\unsloth-install.ps1"
$InstallerMeta = "$Root\forensic\installer.json"
$Response = Invoke-WebRequest -Uri 'https://unsloth.ai/install.ps1' -OutFile $Installer -UseBasicParsing -PassThru
$InstallerHash = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash
$EffectiveUrl = $null
try { $EffectiveUrl = $Response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri } catch {}

[ordered]@{
    downloaded_at = (Get-Date).ToString('o')
    requested_url = 'https://unsloth.ai/install.ps1'
    effective_url = $EffectiveUrl
    sha256 = $InstallerHash
    size = (Get-Item -LiteralPath $Installer).Length
    trust_model = 'Downloaded from the official HTTPS endpoint at execution time; recorded hashes are audit evidence, not independent authenticity verification.'
    uv_installer_sha256 = $UvInstallerHash
} | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $InstallerMeta -Encoding utf8

$InstallLog = "$Root\logs\install-$Stamp.log"
& $Pwsh -NoLogo -NoProfile -File $Installer 2>&1 | Tee-Object -FilePath $InstallLog
$InstallExit = $LASTEXITCODE
if ($InstallExit -ne 0) {
    throw "Official Unsloth installer failed with exit code $InstallExit. Re-run .\install.ps1 -Repair after addressing the error. See $InstallLog"
}

Write-Host "`n=== VALIDATE ===" -ForegroundColor Cyan
foreach ($Relative in $ManagedTopLevel.Keys) {
    Assert-ManagedChildPhysicalLocation `
        -InstallationRoot $Root `
        -Path $ManagedTopLevel[$Relative] `
        -RelativePath $Relative
}
Assert-SafeModelsRoot -InstallationRoot $Root -ModelsRoot $ModelsRoot

$StudioPython = "$Root\runtime\unsloth_studio\Scripts\python.exe"
$StudioCli = "$Root\runtime\bin\unsloth.cmd"
$LlamaServer = "$Root\runtime\llama.cpp\build\bin\Release\llama-server.exe"
foreach ($Required in @($StudioPython, $StudioCli, $LlamaServer)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        throw "Required managed component is missing: $Required. Re-run .\install.ps1 -Repair."
    }
}

& $StudioPython -c @'
from importlib.metadata import version
import torch
print("unsloth      ", version("unsloth"))
print("unsloth-zoo  ", version("unsloth-zoo"))
print("torch        ", version("torch"))
print("CUDA         ", torch.cuda.is_available(), torch.version.cuda)
if not torch.cuda.is_available():
    raise SystemExit("CUDA is not available to PyTorch")
print("GPU          ", torch.cuda.get_device_name(0))
print("Capability   ", torch.cuda.get_device_capability(0))
'@
if ($LASTEXITCODE -ne 0) {
    throw 'Post-install CUDA validation failed. Re-run .\install.ps1 -Repair after addressing the error.'
}

$UserPathAfter = [Environment]::GetEnvironmentVariable('Path', 'User')
$MachinePathAfter = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($UserPathAfter -cne $UserPathBefore) { throw 'User PATH changed during installation.' }
if ($MachinePathAfter -cne $MachinePathBefore) { throw 'Machine PATH changed during installation.' }

$BaselineData = Get-Content -LiteralPath "$Baseline\baseline.json" -Raw | ConvertFrom-Json
$CMakeAfter = (Get-Command cmake.exe -CommandType Application -ErrorAction SilentlyContinue).Source
$NvccAfter = (Get-Command nvcc.exe -CommandType Application -ErrorAction SilentlyContinue).Source
if (-not $BaselineData.CMake -and $CMakeAfter) {
    throw "Unexpected global CMake appeared during installation: $CMakeAfter"
}
if (-not $BaselineData.NVCC -and $NvccAfter) {
    throw "Unexpected global nvcc appeared during installation: $NvccAfter"
}

foreach ($Name in $KnownExternalPaths.Keys) {
    $existedBefore = [bool]$ExternalBefore[$Name]
    $existsAfter = Test-Path -LiteralPath $KnownExternalPaths[$Name]
    if (-not $existedBefore -and $existsAfter) {
        throw "Unexpected external footprint appeared during installation: $($KnownExternalPaths[$Name])"
    }
}

[ordered]@{
    installed_at = (Get-Date).ToString('o')
    mode = if ($Repair) { 'repair' } else { 'install' }
    root = $Root
    models_root = $ModelsRoot
    managed_python = $PythonResolvedFull
    baseline = $Baseline
    installer_sha256 = $InstallerHash
} | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $InstallState -Encoding utf8

Write-Host "`n=== INSTALL COMPLETE ===" -ForegroundColor Green
Write-Host "Root   : $Root"
Write-Host "Models : $ModelsRoot"
Write-Host 'Start  : .\start.ps1'
Write-Host 'Doctor : .\doctor.ps1'
