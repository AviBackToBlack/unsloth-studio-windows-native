$ErrorActionPreference = 'Continue'

$Root = $PSScriptRoot
. "$Root\scripts\common.ps1"
. "$Root\scripts\env.ps1"

$Py = "$Root\runtime\unsloth_studio\Scripts\python.exe"
$Issues = [System.Collections.Generic.List[string]]::new()

Write-Host "`n=== INSTALLATION ===" -ForegroundColor Cyan
[pscustomobject]@{
    Root = $Root
    Models = $script:UnslothModels
    Config = "$Root\config.psd1"
    ConfigExists = Test-Path -LiteralPath "$Root\config.psd1" -PathType Leaf
} | Format-List

try {
    Assert-SafeModelsRoot -InstallationRoot $Root -ModelsRoot $script:UnslothModels
} catch {
    $Issues.Add($_.Exception.Message)
}

if (-not (Test-Path -LiteralPath $Py -PathType Leaf)) {
    $Issues.Add("Managed Studio Python is missing: $Py")
}

if (Test-Path -LiteralPath $Py -PathType Leaf) {
    Write-Host "`n=== UNSLOTH ===" -ForegroundColor Cyan

    & $Py -c @'
from importlib.metadata import version, PackageNotFoundError

required = {"unsloth", "unsloth-zoo", "torch"}
failed = False
for p in (
    "unsloth", "unsloth-zoo", "torch", "torchvision", "torchaudio", "xformers",
):
    try:
        print(f"{p:14} {version(p)}")
    except PackageNotFoundError:
        print(f"{p:14} MISSING")
        if p in required:
            failed = True
raise SystemExit(1 if failed else 0)
'@

    if ($LASTEXITCODE -ne 0) {
        $Issues.Add('One or more required Python packages are missing: unsloth, unsloth-zoo, or torch.')
    }

    Write-Host "`n=== GPU ===" -ForegroundColor Cyan

    & $Py -c @'
import torch
print("CUDA available :", torch.cuda.is_available())
print("Torch CUDA     :", torch.version.cuda)
if torch.cuda.is_available():
    print("GPU            :", torch.cuda.get_device_name(0))
    print("Capability     :", torch.cuda.get_device_capability(0))
raise SystemExit(0 if torch.cuda.is_available() else 2)
'@

    if ($LASTEXITCODE -ne 0) {
        $Issues.Add('CUDA is not available to the managed PyTorch runtime.')
    }

    Write-Host "`n=== STATE ===" -ForegroundColor Cyan

    & $Py -c @'
import os
import sqlite3
from pathlib import Path

root = Path(os.environ["UNSLOTH_NATIVE_ROOT"])
failed = False

for label, path in (
    ("studio", root / "runtime" / "studio.db"),
    ("auth", root / "runtime" / "auth" / "auth.db"),
):
    if not path.exists():
        print(f"{label:10} NOT INITIALIZED")
        failed = True
        continue

    con = None
    try:
        con = sqlite3.connect(path)
        result = con.execute("PRAGMA integrity_check").fetchone()[0]
        print(f"{label:10} {result}")
        if result != "ok":
            failed = True
    except Exception as exc:
        print(f"{label:10} ERROR {exc!r}")
        failed = True
    finally:
        if con is not None:
            con.close()

raise SystemExit(1 if failed else 0)
'@

    if ($LASTEXITCODE -ne 0) {
        $Issues.Add('Studio state database validation failed.')
    }

    Write-Host "`n=== HF CREDENTIAL ===" -ForegroundColor Cyan

    & $Py -c @'
import os, sys
from pathlib import Path
root = Path(os.environ["UNSLOTH_NATIVE_ROOT"])
db = root / "runtime" / "studio.db"
auth = root / "runtime" / "auth" / "auth.db"
if not db.exists() or not auth.exists():
    print("Saved HF token: Studio state not initialized")
    raise SystemExit(0)
backend = root / "runtime" / "unsloth_studio" / "Lib" / "site-packages" / "studio" / "backend"
sys.path.insert(0, str(backend))
from storage.credential_secrets import has_secret
print("Saved HF token decrypts:", has_secret("hf_token", "default"))
'@
    if ($LASTEXITCODE -ne 0) {
        $Issues.Add('Could not validate the saved Hugging Face credential state.')
    }

    Write-Host "`n=== MODEL FOLDERS ===" -ForegroundColor Cyan

    & $Py -c @'
import os, sqlite3
from pathlib import Path
root = Path(os.environ["UNSLOTH_NATIVE_ROOT"])
db = root / "runtime" / "studio.db"
if not db.exists():
    print("Studio state not initialized")
    raise SystemExit(0)
con = sqlite3.connect(db)
try:
    for _, path in con.execute("SELECT id, path FROM scan_folders ORDER BY id"):
        p = Path(path)
        print(f"{p}  exists={p.is_dir()}")
finally:
    con.close()
'@
    if ($LASTEXITCODE -ne 0) {
        $Issues.Add('Could not read Studio model scan folders.')
    }
}

Write-Host "`n=== MANAGED COMPONENTS ===" -ForegroundColor Cyan
$ManagedPaths = @(
    "$Root\tools\uv\uv.exe"
    "$Root\runtime\bin\unsloth.cmd"
    "$Root\runtime\llama.cpp\build\bin\Release\llama-server.exe"
    "$Root\runtime\whisper.cpp\build\bin\Release\whisper-server.exe"
    "$Root\runtime\node\node.exe"
)

if ($script:UnslothBasePython) {
    $ManagedPaths = @($ManagedPaths[0], $script:UnslothBasePython) + $ManagedPaths[1..($ManagedPaths.Count - 1)]
} else {
    $Issues.Add('Could not resolve a contained managed base Python 3.13 interpreter.')
}

$ManagedRows = foreach ($Path in $ManagedPaths) {
    $Exists = Test-Path -LiteralPath $Path -PathType Leaf
    if (-not $Exists) { $Issues.Add("Managed component missing: $Path") }
    [pscustomobject]@{ Path = $Path; Exists = $Exists }
}
$ManagedRows | Format-Table -AutoSize

Write-Host "`n=== MANAGED PROCESSES ===" -ForegroundColor Cyan
$ManagedProcesses = @()
$ProcessEnumerationSucceeded = $false
try {
    $ManagedProcesses = @(Get-UnslothManagedProcesses -InstallationRoot $Root)
    $ProcessEnumerationSucceeded = $true
    if ($ManagedProcesses.Count -gt 0) {
        $ManagedProcesses | Select-Object ProcessId, ParentProcessId, Name, ExecutablePath | Format-Table -AutoSize
    } else {
        Write-Host 'None'
    }
} catch {
    Write-Warning $_.Exception.Message
    $Issues.Add('Could not enumerate managed processes through CIM/WMI.')
}

function Test-PersistentPathContainsRoot {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    foreach ($entry in ($PathValue -split ';')) {
        $candidate = $entry.Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $candidate = [Environment]::ExpandEnvironmentVariables($candidate)
        if (-not [System.IO.Path]::IsPathFullyQualified($candidate)) {
            continue
        }

        try {
            if (Test-PathInsideOrEqual -Path $candidate -Parent $Root -PhysicalWhenPossible) {
                return $true
            }
        } catch {
            # Diagnostics should not turn a malformed unrelated PATH entry into
            # an installation leak. It remains visible in the user's PATH itself.
            continue
        }
    }

    return $false
}

Write-Host "`n=== ISOLATION ===" -ForegroundColor Cyan
$UserPersistentPath = [Environment]::GetEnvironmentVariable('Path','User')
$MachinePersistentPath = [Environment]::GetEnvironmentVariable('Path','Machine')
$UserPathHasRoot = Test-PersistentPathContainsRoot $UserPersistentPath
$MachinePathHasRoot = Test-PersistentPathContainsRoot $MachinePersistentPath

[pscustomobject]@{
    UserPathHasInstallationRoot = $UserPathHasRoot
    MachinePathHasInstallationRoot = $MachinePathHasRoot
    GlobalCMake = (Get-Command cmake.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    GlobalNVCC = (Get-Command nvcc.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    TorchInductorCache = $env:TORCHINDUCTOR_CACHE_DIR
} | Format-List

if ($UserPathHasRoot) { $Issues.Add('Installation root appears in persistent User PATH.') }
if ($MachinePathHasRoot) { $Issues.Add('Installation root appears in persistent Machine PATH.') }

Write-Host "`n=== EXTERNAL FOOTPRINT ===" -ForegroundColor Cyan
$UvReceipt = "$env:LOCALAPPDATA\uv\uv-receipt.json"
@(
    "$env:USERPROFILE\.unsloth"
    "$env:LOCALAPPDATA\Unsloth Studio"
    "$env:APPDATA\Unsloth Studio"
    $UvReceipt
) | ForEach-Object { [pscustomobject]@{ Path = $_; Exists = Test-Path -LiteralPath $_ } } | Format-Table -AutoSize

if (Test-Path -LiteralPath $UvReceipt -PathType Leaf) {
    try {
        $Receipt = Get-Content -LiteralPath $UvReceipt -Raw | ConvertFrom-Json
        Write-Host "uv receipt install_prefix: $($Receipt.install_prefix)"
    } catch {
        $Issues.Add("Could not parse uv receipt: $UvReceipt")
    }
}

Write-Host "`n=== SERVER ===" -ForegroundColor Cyan
$Health = $null
$HealthSucceeded = $false
try {
    $Health = Invoke-RestMethod "http://127.0.0.1:$($script:UnslothPort)/api/health" -TimeoutSec 2
    $HealthSucceeded = $true
} catch {}

$ListenerEnumerationSucceeded = $false
$Listeners = @()
try {
    $Listeners = @(
        Get-NetTCPConnection -State Listen -LocalPort $script:UnslothPort -ErrorAction Stop
    )
    $ListenerEnumerationSucceeded = $true
} catch {
    # Get-NetTCPConnection throws both when the provider is unavailable and when
    # no matching listener exists. Distinguish the ordinary no-listener case.
    try {
        $allListeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop)
        $Listeners = @($allListeners | Where-Object { $_.LocalPort -eq $script:UnslothPort })
        $ListenerEnumerationSucceeded = $true
    } catch {
        $Issues.Add('Could not enumerate TCP listener ownership.')
    }
}

$ManagedPids = @{}
foreach ($process in $ManagedProcesses) {
    $ManagedPids[[int]$process.ProcessId] = $true
}
$ManagedListeners = @(
    $Listeners | Where-Object { $ManagedPids.ContainsKey([int]$_.OwningProcess) }
)

if (-not $ProcessEnumerationSucceeded -or -not $ListenerEnumerationSucceeded) {
    if ($HealthSucceeded) {
        Write-Host 'Studio server: UNKNOWN (health responded, ownership could not be established)' -ForegroundColor Yellow
    } else {
        Write-Host 'Studio server: UNKNOWN (ownership could not be established)' -ForegroundColor Yellow
    }
} elseif ($ManagedListeners.Count -gt 0 -and $HealthSucceeded) {
    Write-Host 'Studio server: RUNNING (managed listener PID + health endpoint)' -ForegroundColor Green
    $ManagedListeners | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table -AutoSize
    $Health | ConvertTo-Json -Depth 5
} elseif ($ManagedListeners.Count -gt 0 -and -not $HealthSucceeded) {
    Write-Host 'Studio server: MANAGED LISTENER PRESENT, HEALTH CHECK FAILED' -ForegroundColor Red
    $Issues.Add('This installation owns the configured Studio listener, but its health endpoint did not respond.')
} elseif ($ManagedListeners.Count -eq 0 -and $HealthSucceeded) {
    Write-Host 'Studio server: UNMANAGED LISTENER / NOT THIS INSTALLATION' -ForegroundColor Red
    $Issues.Add('The Studio health URL responded, but the configured listener is not owned by this installation.')
} elseif ($Listeners.Count -gt 0) {
    Write-Host 'Studio server: PORT OWNED BY ANOTHER PROCESS' -ForegroundColor Red
    $Issues.Add('The configured Studio port is listening, but its owning PID is not managed by this installation.')
} else {
    Write-Host 'Studio server: STOPPED' -ForegroundColor DarkGray
}

Write-Host "`n=== DOCTOR RESULT ===" -ForegroundColor Cyan
if ($Issues.Count -eq 0) {
    Write-Host 'HEALTHY' -ForegroundColor Green
    exit 0
}
$Issues | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
exit 1
