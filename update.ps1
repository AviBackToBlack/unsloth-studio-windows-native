$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot

. "$Root\scripts\env.ps1"

$Cli = "$Root\runtime\bin\unsloth.cmd"
$Py  = "$Root\runtime\unsloth_studio\Scripts\python.exe"

if (-not (Test-Path $Cli)) {
    throw "Managed Unsloth CLI not found: $Cli"
}

if (-not (Test-Path $Py)) {
    throw "Managed Studio Python not found: $Py"
}

# ------------------------------------------------------------------
# Studio must be stopped
# ------------------------------------------------------------------

if (Get-NetTCPConnection `
        -LocalPort 8888 `
        -State Listen `
        -ErrorAction SilentlyContinue) {

    throw 'Unsloth Studio is running on port 8888. Stop it before updating.'
}

# ------------------------------------------------------------------
# Snapshot current state
# ------------------------------------------------------------------

$Stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup = "$Root\forensic\updates\$Stamp"

New-Item -ItemType Directory -Force $Backup | Out-Null

foreach ($File in @(
    "$Root\runtime\studio.db"
    "$Root\runtime\auth\auth.db"
)) {
    if (Test-Path $File) {
        Copy-Item $File $Backup
    }
}

Write-Host "`n=== BEFORE ===" -ForegroundColor Cyan

& $Py -c @'
from importlib.metadata import version, PackageNotFoundError

for p in ("unsloth", "unsloth-zoo", "torch", "xformers"):
    try:
        print(f"{p:12} {version(p)}")
    except PackageNotFoundError:
        print(f"{p:12} NOT INSTALLED")
'@

# ------------------------------------------------------------------
# Official update
# ------------------------------------------------------------------

Write-Host "`n=== UNSLOTH STUDIO UPDATE ===" -ForegroundColor Cyan

& $Cli studio update

if ($LASTEXITCODE -ne 0) {
    throw "Unsloth Studio update failed: exit code $LASTEXITCODE"
}

# ------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------

Write-Host "`n=== AFTER ===" -ForegroundColor Cyan

& $Py -c @'
from importlib.metadata import version, PackageNotFoundError
import torch

for p in ("unsloth", "unsloth-zoo", "torch", "xformers"):
    try:
        print(f"{p:12} {version(p)}")
    except PackageNotFoundError:
        print(f"{p:12} NOT INSTALLED")

print()
print("CUDA available :", torch.cuda.is_available())
print("CUDA runtime   :", torch.version.cuda)

if torch.cuda.is_available():
    print("GPU            :", torch.cuda.get_device_name(0))
    print("Capability     :", torch.cuda.get_device_capability(0))

if not torch.cuda.is_available():
    raise SystemExit("CUDA validation FAILED")
'@

if ($LASTEXITCODE -ne 0) {
    throw 'Post-update CUDA validation failed.'
}

Write-Host "`n=== STATE ===" -ForegroundColor Cyan

& $Py -c @'
import sqlite3
from pathlib import Path

root = Path(r"D:\AI\Unsloth")

for name, p in (
    ("studio", root / "runtime" / "studio.db"),
    ("auth",   root / "runtime" / "auth" / "auth.db"),
):
    con = sqlite3.connect(p)
    print(name, con.execute("PRAGMA integrity_check").fetchone()[0])
    con.close()
'@

Write-Host "`n=== TOOLCHAIN LEAK CHECK ===" -ForegroundColor Cyan

[pscustomobject]@{
    CMake = (
        Get-Command cmake.exe `
            -CommandType Application `
            -ErrorAction SilentlyContinue
    ).Source

    NVCC = (
        Get-Command nvcc.exe `
            -CommandType Application `
            -ErrorAction SilentlyContinue
    ).Source
} | Format-List

Write-Host "Backup: $Backup" -ForegroundColor DarkGray
Write-Host "`n=== UPDATE COMPLETE ===" -ForegroundColor Green
