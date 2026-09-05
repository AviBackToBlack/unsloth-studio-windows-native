$ErrorActionPreference = 'Continue'

$Root = $PSScriptRoot
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

if (-not (Test-Path -LiteralPath $Py -PathType Leaf)) {
    $Issues.Add("Managed Studio Python is missing: $Py")
}

if (Test-Path -LiteralPath $Py -PathType Leaf) {
    Write-Host "`n=== UNSLOTH ===" -ForegroundColor Cyan

    & $Py -c @'
from importlib.metadata import version, PackageNotFoundError

for p in (
    "unsloth", "unsloth-zoo", "torch", "torchvision", "torchaudio", "xformers",
):
    try:
        print(f"{p:14} {version(p)}")
    except PackageNotFoundError:
        print(f"{p:14} MISSING")
'@

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
import os, sqlite3
from pathlib import Path
root = Path(os.environ["UNSLOTH_NATIVE_ROOT"])
for label, path in (
    ("studio", root / "runtime" / "studio.db"),
    ("auth", root / "runtime" / "auth" / "auth.db"),
):
    if not path.exists():
        print(f"{label:10} NOT INITIALIZED")
        continue
    con = sqlite3.connect(path)
    print(f"{label:10} {con.execute('PRAGMA integrity_check').fetchone()[0]}")
    con.close()
'@

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
for _, path in con.execute("SELECT id, path FROM scan_folders ORDER BY id"):
    p = Path(path)
    print(f"{p}  exists={p.is_dir()}")
con.close()
'@
}

Write-Host "`n=== MANAGED COMPONENTS ===" -ForegroundColor Cyan
$ManagedRows = foreach ($Path in @(
    "$Root\tools\uv\uv.exe"
    "$Root\python\cpython-3.13-windows-x86_64-none\python.exe"
    "$Root\runtime\bin\unsloth.cmd"
    "$Root\runtime\llama.cpp\build\bin\Release\llama-server.exe"
    "$Root\runtime\whisper.cpp\build\bin\Release\whisper-server.exe"
    "$Root\runtime\node\node.exe"
)) {
    $Exists = Test-Path -LiteralPath $Path -PathType Leaf
    if (-not $Exists) { $Issues.Add("Managed component missing: $Path") }
    [pscustomobject]@{ Path = $Path; Exists = $Exists }
}
$ManagedRows | Format-Table -AutoSize

Write-Host "`n=== ISOLATION ===" -ForegroundColor Cyan
$UserPathHasRoot = [Environment]::GetEnvironmentVariable('Path','User') -match [regex]::Escape($Root)
$MachinePathHasRoot = [Environment]::GetEnvironmentVariable('Path','Machine') -match [regex]::Escape($Root)

[pscustomobject]@{
    UserPathHasInstallationRoot = $UserPathHasRoot
    MachinePathHasInstallationRoot = $MachinePathHasRoot
    GlobalCMake = (Get-Command cmake.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    GlobalNVCC = (Get-Command nvcc.exe -CommandType Application -ErrorAction SilentlyContinue).Source
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
try {
    $Health = Invoke-RestMethod "http://127.0.0.1:$($script:UnslothPort)/api/health" -TimeoutSec 2
    Write-Host 'Studio server: RUNNING' -ForegroundColor Green
    $Health | ConvertTo-Json -Depth 5
} catch {
    Write-Host 'Studio server: STOPPED' -ForegroundColor DarkGray
}

Write-Host "`n=== DOCTOR RESULT ===" -ForegroundColor Cyan
if ($Issues.Count -eq 0) {
    Write-Host 'HEALTHY' -ForegroundColor Green
    exit 0
}
$Issues | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
exit 1
