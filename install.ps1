[CmdletBinding()]
param(
    [string]$ModelsRoot
)

$ErrorActionPreference = 'Stop'

$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$Pwsh = (Get-Process -Id $PID).Path

if (-not $IsWindows) {
    throw 'This installer supports Windows only.'
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or newer is required. Run this script from pwsh.exe.'
}

if (-not [Environment]::Is64BitProcess) {
    throw 'Run the installer from 64-bit PowerShell.'
}

if (Test-Path -LiteralPath "$Root\runtime\unsloth_studio" -PathType Container) {
    throw 'Unsloth Studio already appears to be installed. Use .\update.ps1 instead.'
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

if ([string]::IsNullOrWhiteSpace($ModelsRoot)) {
    $ModelsRoot = Join-Path $Root 'models'
} elseif (-not [System.IO.Path]::IsPathRooted($ModelsRoot)) {
    throw '-ModelsRoot must be an absolute path.'
} else {
    $ModelsRoot = [System.IO.Path]::GetFullPath($ModelsRoot)
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

$escapedModelsRoot = $ModelsRoot.Replace("'", "''")
@"
@{
    ModelsRoot = '$escapedModelsRoot'
    Port = 8888
    BindHost = '127.0.0.1'
}
"@ | Set-Content -LiteralPath "$Root\config.psd1" -Encoding utf8

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Baseline = "$Root\forensic\preinstall\$Stamp"
[System.IO.Directory]::CreateDirectory($Baseline) | Out-Null

$UserPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
$MachinePathBefore = [Environment]::GetEnvironmentVariable('Path', 'Machine')

[pscustomobject]@{
    Timestamp = (Get-Date).ToString('o')
    Root = $Root
    ModelsRoot = $ModelsRoot
    UserPath = $UserPathBefore
    MachinePath = $MachinePathBefore
    CMake = (Get-Command cmake.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    NVCC = (Get-Command nvcc.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    Node = (Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    Python = (Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    ProfileUnsloth = Test-Path -LiteralPath "$env:USERPROFILE\.unsloth"
    LocalAppDataUnsloth = Test-Path -LiteralPath "$env:LOCALAPPDATA\Unsloth Studio"
    RoamingAppDataUnsloth = Test-Path -LiteralPath "$env:APPDATA\Unsloth Studio"
} | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath "$Baseline\baseline.json" -Encoding utf8

Write-Host "`nBaseline: $Baseline" -ForegroundColor DarkGray

. "$Root\scripts\env.ps1"

Write-Host "`n=== INSTALL UV ===" -ForegroundColor Cyan
$UvInstaller = "$Root\work\uv-install.ps1"
Invoke-WebRequest -Uri 'https://astral.sh/uv/install.ps1' -OutFile $UvInstaller -UseBasicParsing
& $Pwsh -NoLogo -NoProfile -File $UvInstaller
if ($LASTEXITCODE -ne 0) {
    throw "uv installer failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $script:UnslothUv -PathType Leaf)) {
    throw "uv was not installed at the expected path: $script:UnslothUv"
}
& $script:UnslothUv --version

Write-Host "`n=== INSTALL PYTHON 3.13 ===" -ForegroundColor Cyan
& $script:UnslothUv python install 3.13 --no-bin --no-config
if ($LASTEXITCODE -ne 0) {
    throw "uv python install failed with exit code $LASTEXITCODE"
}

$ResolvedPython = (& $script:UnslothUv python find --managed-python 3.13).Trim()
if (-not $ResolvedPython -or -not (Test-Path -LiteralPath $ResolvedPython -PathType Leaf)) {
    throw 'Could not resolve the uv-managed Python 3.13 interpreter.'
}

$PythonRootExpected = [System.IO.Path]::GetFullPath("$Root\python")
$PythonResolvedFull = [System.IO.Path]::GetFullPath($ResolvedPython)
if (-not $PythonResolvedFull.StartsWith($PythonRootExpected, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Managed Python escaped the installation root: $PythonResolvedFull"
}
& $ResolvedPython --version

Write-Host "`n=== INSTALL UNSLOTH STUDIO ===" -ForegroundColor Cyan
$Installer = "$Root\work\unsloth-install.ps1"
$InstallerMeta = "$Root\forensic\installer.json"
$Response = Invoke-WebRequest -Uri 'https://unsloth.ai/install.ps1' -OutFile $Installer -UseBasicParsing
$InstallerHash = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash
$EffectiveUrl = $null
try { $EffectiveUrl = $Response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri } catch {}

[ordered]@{
    downloaded_at = (Get-Date).ToString('o')
    requested_url = 'https://unsloth.ai/install.ps1'
    effective_url = $EffectiveUrl
    sha256 = $InstallerHash
    size = (Get-Item -LiteralPath $Installer).Length
} | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $InstallerMeta -Encoding utf8

$InstallLog = "$Root\logs\install-$Stamp.log"
& $Pwsh -NoLogo -NoProfile -File $Installer 2>&1 | Tee-Object -FilePath $InstallLog
$InstallExit = $LASTEXITCODE
if ($InstallExit -ne 0) {
    throw "Official Unsloth installer failed with exit code $InstallExit. See $InstallLog"
}

Write-Host "`n=== VALIDATE ===" -ForegroundColor Cyan
$StudioPython = "$Root\runtime\unsloth_studio\Scripts\python.exe"
$StudioCli = "$Root\runtime\bin\unsloth.cmd"
$LlamaServer = "$Root\runtime\llama.cpp\build\bin\Release\llama-server.exe"
foreach ($Required in @($StudioPython, $StudioCli, $LlamaServer)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        throw "Required managed component is missing: $Required"
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
    throw 'Post-install CUDA validation failed.'
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

[ordered]@{
    installed_at = (Get-Date).ToString('o')
    root = $Root
    models_root = $ModelsRoot
    baseline = $Baseline
    installer_sha256 = $InstallerHash
} | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath "$Root\forensic\install-state.json" -Encoding utf8

Write-Host "`n=== INSTALL COMPLETE ===" -ForegroundColor Green
Write-Host "Root   : $Root"
Write-Host "Models : $ModelsRoot"
Write-Host 'Start  : .\start.ps1'
Write-Host 'Doctor : .\doctor.ps1'
