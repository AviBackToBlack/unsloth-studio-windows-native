[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$RemoveModels
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
. "$Root\scripts\env.ps1"

if (Get-NetTCPConnection -LocalPort $script:UnslothPort -State Listen -ErrorAction SilentlyContinue) {
    throw "A process is listening on Studio port $script:UnslothPort. Stop Studio before uninstalling."
}

Write-Host "`nUnsloth Studio native installation" -ForegroundColor Cyan
Write-Host "Root   : $Root"
Write-Host "Models : $script:UnslothModels"
Write-Host ''
Write-Host 'Repository scripts and LICENSE will be kept.'
Write-Host 'External model libraries are never deleted.'

$OwnedPaths = @(
    "$Root\runtime"
    "$Root\tools"
    "$Root\python"
    "$Root\cache"
    "$Root\logs"
    "$Root\work"
    "$Root\forensic"
)

foreach ($Path in $OwnedPaths) {
    if ((Test-Path -LiteralPath $Path) -and $PSCmdlet.ShouldProcess($Path, 'Remove managed installation data')) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

$DefaultModels = [System.IO.Path]::GetFullPath("$Root\models")
$ActualModels = [System.IO.Path]::GetFullPath($script:UnslothModels)

if ($RemoveModels) {
    if (-not $ActualModels.Equals($DefaultModels, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "ModelsRoot is external and will NOT be deleted: $ActualModels"
    } elseif ((Test-Path -LiteralPath $DefaultModels) -and $PSCmdlet.ShouldProcess($DefaultModels, 'Remove local models')) {
        Remove-Item -LiteralPath $DefaultModels -Recurse -Force
    }
} elseif (Test-Path -LiteralPath $ActualModels) {
    Write-Host "Models preserved: $ActualModels" -ForegroundColor Yellow
}

$UvReceipt = "$env:LOCALAPPDATA\uv\uv-receipt.json"
if (Test-Path -LiteralPath $UvReceipt -PathType Leaf) {
    try {
        $Receipt = Get-Content -LiteralPath $UvReceipt -Raw | ConvertFrom-Json
        $ExpectedPrefix = [System.IO.Path]::GetFullPath("$Root\tools\uv")

        if ($Receipt.install_prefix -and [System.IO.Path]::GetFullPath([string]$Receipt.install_prefix).Equals($ExpectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($PSCmdlet.ShouldProcess($UvReceipt, 'Remove owned uv installer receipt')) {
                Remove-Item -LiteralPath $UvReceipt -Force
            }
        } else {
            Write-Host "uv receipt is not owned by this installation; preserved: $UvReceipt"
        }
    } catch {
        Write-Warning "Could not verify ownership of uv receipt; preserved: $UvReceipt"
    }
}

$Config = "$Root\config.psd1"
if ((Test-Path -LiteralPath $Config -PathType Leaf) -and $PSCmdlet.ShouldProcess($Config, 'Remove local installation configuration')) {
    Remove-Item -LiteralPath $Config -Force
}

Write-Host "`n=== UNINSTALL COMPLETE ===" -ForegroundColor Green
Write-Host 'Repository files were preserved.'
