$ErrorActionPreference = 'Continue'

$Root = $PSScriptRoot
. "$Root\scripts\env.ps1"

$Py = "$Root\runtime\unsloth_studio\Scripts\python.exe"

Write-Host "`n=== UNSLOTH ===" -ForegroundColor Cyan

& $Py -c @'
from importlib.metadata import version, PackageNotFoundError

for p in (
    "unsloth",
    "unsloth-zoo",
    "torch",
    "torchvision",
    "torchaudio",
    "xformers",
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
'@

Write-Host "`n=== STATE ===" -ForegroundColor Cyan

& $Py -c @'
import sqlite3
from pathlib import Path

root = Path(r"D:\AI\Unsloth")

for label, path in (
    ("studio", root / "runtime" / "studio.db"),
    ("auth",   root / "runtime" / "auth" / "auth.db"),
):
    if not path.exists():
        print(f"{label:10} MISSING")
        continue

    con = sqlite3.connect(path)
    print(f"{label:10} {con.execute('PRAGMA integrity_check').fetchone()[0]}")
    con.close()
'@

Write-Host "`n=== HF CREDENTIAL ===" -ForegroundColor Cyan

& $Py -c @'
import sys
from pathlib import Path

backend = (
    Path(r"D:\AI\Unsloth\runtime\unsloth_studio")
    / "Lib" / "site-packages" / "studio" / "backend"
)

sys.path.insert(0, str(backend))

from storage.credential_secrets import has_secret

print(
    "Saved HF token decrypts:",
    has_secret("hf_token", "default")
)
'@

Write-Host "`n=== MODEL FOLDERS ===" -ForegroundColor Cyan

& $Py -c @'
import sqlite3
from pathlib import Path

db = Path(r"D:\AI\Unsloth\runtime\studio.db")

con = sqlite3.connect(db)

for _, path in con.execute(
    "SELECT id, path FROM scan_folders ORDER BY id"
):
    p = Path(path)
    print(f"{p}  exists={p.is_dir()}")

con.close()
'@

Write-Host "`n=== MANAGED COMPONENTS ===" -ForegroundColor Cyan

@(
    "$Root\tools\uv\uv.exe"
    "$Root\python\cpython-3.13-windows-x86_64-none\python.exe"
    "$Root\runtime\bin\unsloth.cmd"
    "$Root\runtime\llama.cpp\build\bin\Release\llama-server.exe"
    "$Root\runtime\whisper.cpp\build\bin\Release\whisper-server.exe"
    "$Root\runtime\node\node.exe"
) | ForEach-Object {
    [pscustomobject]@{
        Path   = $_
        Exists = Test-Path -LiteralPath $_
    }
} | Format-Table -AutoSize

Write-Host "`n=== ISOLATION ===" -ForegroundColor Cyan

[pscustomobject]@{
    UserPathHasUnsloth = (
        [Environment]::GetEnvironmentVariable('Path','User') -match
        [regex]::Escape($Root)
    )

    MachinePathHasUnsloth = (
        [Environment]::GetEnvironmentVariable('Path','Machine') -match
        [regex]::Escape($Root)
    )

    CMake = [bool](
        Get-Command cmake.exe `
            -CommandType Application `
            -ErrorAction SilentlyContinue
    )

    NVCC = [bool](
        Get-Command nvcc.exe `
            -CommandType Application `
            -ErrorAction SilentlyContinue
    )
} | Format-List

Write-Host "`n=== EXTERNAL FOOTPRINT ===" -ForegroundColor Cyan

@(
    "$env:USERPROFILE\.unsloth"
    "$env:LOCALAPPDATA\Unsloth Studio"
    "$env:APPDATA\Unsloth Studio"
    "$env:LOCALAPPDATA\uv\uv-receipt.json"
) | ForEach-Object {
    [pscustomobject]@{
        Path   = $_
        Exists = Test-Path -LiteralPath $_
    }
} | Format-Table -AutoSize

Write-Host "`n=== SERVER ===" -ForegroundColor Cyan

try {
    $Health = Invoke-RestMethod `
        'http://127.0.0.1:8888/api/health' `
        -TimeoutSec 2

    Write-Host 'Studio server: RUNNING' -ForegroundColor Green
    $Health | ConvertTo-Json -Depth 5
}
catch {
    Write-Host 'Studio server: STOPPED' -ForegroundColor DarkGray
}

Write-Host "`n=== DOCTOR COMPLETE ===" -ForegroundColor Green
