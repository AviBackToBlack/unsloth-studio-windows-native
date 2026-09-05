param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$')]
    [string]$RepoId,

    [string]$Revision = 'main',

    [string[]]$Include = @(),

    [string[]]$Exclude = @(),

    [ValidateSet('Filtered', 'All')]
    [string]$Mode = 'Filtered',

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = $PSScriptRoot
. "$Root\scripts\env.ps1"

$Py = "$Root\runtime\unsloth_studio\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $Py -PathType Leaf)) {
    throw 'Unsloth Studio is not installed.'
}

if ($Mode -eq 'All' -and $Include.Count -gt 0) {
    throw 'Use either -Mode All or -Include, not both.'
}

if ($Mode -eq 'Filtered' -and $Include.Count -eq 0) {
    throw 'Filtered mode requires -Include. Use -Mode All to explicitly download the entire repository.'
}

$Org, $Model = $RepoId -split '/', 2
$Target = Join-Path $script:UnslothModels "huggingface\$Org\$Model"
$ScanRoot = Split-Path $Target -Parent

Write-Host "`n=== MODEL SYNC ===" -ForegroundColor Cyan
Write-Host "Repo     : $RepoId"
Write-Host "Revision : $Revision"
Write-Host "Target   : $Target"
Write-Host "Mode     : $(if ($Apply) { 'DOWNLOAD' } else { 'DRY RUN' })"
if ($Include.Count) { Write-Host "Include  : $($Include -join ', ')" }
if ($Exclude.Count) { Write-Host "Exclude  : $($Exclude -join ', ')" }

$env:_UNSLOTH_SYNC_REPO = $RepoId
$env:_UNSLOTH_SYNC_REVISION = $Revision
$env:_UNSLOTH_SYNC_TARGET = $Target
$env:_UNSLOTH_SYNC_SCANROOT = $ScanRoot
$env:_UNSLOTH_SYNC_INCLUDE = ConvertTo-Json -InputObject @($Include) -Compress
$env:_UNSLOTH_SYNC_EXCLUDE = ConvertTo-Json -InputObject @($Exclude) -Compress
$env:_UNSLOTH_SYNC_APPLY = if ($Apply) { '1' } else { '0' }

$Code = @'
import json
import os
import sys
from pathlib import Path

from huggingface_hub import snapshot_download

root = Path(os.environ["UNSLOTH_NATIVE_ROOT"])
backend = root / "runtime" / "unsloth_studio" / "Lib" / "site-packages" / "studio" / "backend"
sys.path.insert(0, str(backend))

from storage.credential_secrets import get_hf_token

repo_id = os.environ["_UNSLOTH_SYNC_REPO"]
revision = os.environ["_UNSLOTH_SYNC_REVISION"]
target = Path(os.environ["_UNSLOTH_SYNC_TARGET"])
scanroot = Path(os.environ["_UNSLOTH_SYNC_SCANROOT"])
include = json.loads(os.environ["_UNSLOTH_SYNC_INCLUDE"])
exclude = json.loads(os.environ["_UNSLOTH_SYNC_EXCLUDE"])
apply = os.environ["_UNSLOTH_SYNC_APPLY"] == "1"

token = get_hf_token()
if not token:
    raise SystemExit(
        "Saved Hugging Face token is missing. Sign in to Hugging Face from Unsloth Studio first."
    )

kwargs = dict(
    repo_id=repo_id,
    revision=revision,
    token=token,
    local_dir=target,
    allow_patterns=include or None,
    ignore_patterns=exclude or None,
)

if not apply:
    print("\n=== DRY RUN ===")
    infos = snapshot_download(**kwargs, dry_run=True)
    total = 0
    count = 0
    for info in sorted(infos, key=lambda x: x.filename):
        name = info.filename
        size = int(info.file_size or 0)
        will_download = bool(info.will_download)
        status = "DOWNLOAD" if will_download else "PRESENT"
        if will_download:
            count += 1
            total += size
        print(f"{status:8} {size / 1024**3:10.3f} GiB  {name}")
    print()
    print(f"Files to download : {count}")
    print(f"Bytes to download : {total}")
    print(f"Download size     : {total / 1024**3:.3f} GiB")
    print("\nDry run only. Re-run with -Apply to download.")
    raise SystemExit(0)

print("\n=== DOWNLOADING ===")
result = snapshot_download(**kwargs)
print("\nDownload complete:")
print(result)

from storage.studio_db import add_scan_folder_with_status
folder, inserted = add_scan_folder_with_status(str(scanroot))
print("\n=== STUDIO SCAN FOLDER ===")
print("path :", folder["path"])
print("new  :", inserted)

metadata_root = target / ".cache" / "huggingface"
payload_bytes = payload_files = metadata_bytes = metadata_files = 0
for p in target.rglob("*"):
    if not p.is_file():
        continue
    try:
        size = p.stat().st_size
    except OSError:
        continue
    try:
        p.relative_to(metadata_root)
        metadata_files += 1
        metadata_bytes += size
    except ValueError:
        payload_files += 1
        payload_bytes += size

print("\n=== DISK USAGE ===")
print(f"Payload  : {payload_files} files, {payload_bytes / 1024**3:.3f} GiB")
print(f"Metadata : {metadata_files} files, {metadata_bytes / 1024**2:.3f} MiB")
'@

try {
    & $Py -c $Code
    if ($LASTEXITCODE -ne 0) {
        throw "Model sync failed with exit code $LASTEXITCODE"
    }
} finally {
    @(
        '_UNSLOTH_SYNC_REPO'
        '_UNSLOTH_SYNC_REVISION'
        '_UNSLOTH_SYNC_TARGET'
        '_UNSLOTH_SYNC_SCANROOT'
        '_UNSLOTH_SYNC_INCLUDE'
        '_UNSLOTH_SYNC_EXCLUDE'
        '_UNSLOTH_SYNC_APPLY'
    ) | ForEach-Object {
        Remove-Item "Env:$_" -ErrorAction SilentlyContinue
    }
}
