$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
. "$Root\scripts\common.ps1"
. "$Root\scripts\env.ps1"

$Cli = "$Root\runtime\bin\unsloth.cmd"
$Py = "$Root\runtime\unsloth_studio\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $Cli -PathType Leaf)) {
    throw 'Unsloth Studio is not installed.'
}

if (-not (Test-Path -LiteralPath $Py -PathType Leaf)) {
    throw "Managed Studio Python not found: $Py"
}

Assert-UnslothStopped -InstallationRoot $Root

$UserPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
$MachinePathBefore = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$CMakeBefore = (Get-Command cmake.exe -CommandType Application -ErrorAction SilentlyContinue).Source
$NvccBefore = (Get-Command nvcc.exe -CommandType Application -ErrorAction SilentlyContinue).Source

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup = "$Root\forensic\updates\$Stamp"
New-Item -ItemType Directory -Force $Backup | Out-Null

foreach ($File in @(
    "$Root\runtime\studio.db"
    "$Root\runtime\auth\auth.db"
)) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw "Required Studio state database is missing: $File"
    }
    Copy-Item -LiteralPath $File -Destination $Backup
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

Write-Host "`n=== OFFICIAL UNSLOTH STUDIO UPDATE ===" -ForegroundColor Cyan

& $Cli studio update

if ($LASTEXITCODE -ne 0) {
    throw "Unsloth Studio update failed with exit code $LASTEXITCODE"
}

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
import os
import sqlite3
from pathlib import Path

root = Path(os.environ["UNSLOTH_NATIVE_ROOT"])
failed = False

for name, p in (
    ("studio", root / "runtime" / "studio.db"),
    ("auth", root / "runtime" / "auth" / "auth.db"),
):
    if not p.exists():
        print(name, "MISSING")
        failed = True
        continue

    con = None
    try:
        con = sqlite3.connect(p)
        result = con.execute("PRAGMA integrity_check").fetchone()[0]
        print(name, result)
        if result != "ok":
            failed = True
    except Exception as exc:
        print(name, "ERROR", repr(exc))
        failed = True
    finally:
        if con is not None:
            con.close()

raise SystemExit(1 if failed else 0)
'@

if ($LASTEXITCODE -ne 0) {
    throw "Database integrity validation failed after update. Backup is available at: $Backup"
}

$UserPathAfter = [Environment]::GetEnvironmentVariable('Path', 'User')
$MachinePathAfter = [Environment]::GetEnvironmentVariable('Path', 'Machine')

if ($UserPathAfter -cne $UserPathBefore) {
    throw 'User PATH changed during update.'
}

if ($MachinePathAfter -cne $MachinePathBefore) {
    throw 'Machine PATH changed during update.'
}

$CMakeAfter = (Get-Command cmake.exe -CommandType Application -ErrorAction SilentlyContinue).Source
$NvccAfter = (Get-Command nvcc.exe -CommandType Application -ErrorAction SilentlyContinue).Source

if (-not $CMakeBefore -and $CMakeAfter) {
    throw "Unexpected global CMake appeared during update: $CMakeAfter"
}

if (-not $NvccBefore -and $NvccAfter) {
    throw "Unexpected global nvcc appeared during update: $NvccAfter"
}

Write-Host "Backup: $Backup" -ForegroundColor DarkGray
Write-Host "`n=== UPDATE COMPLETE ===" -ForegroundColor Green
