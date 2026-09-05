[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$RemoveModels
)

$ErrorActionPreference = 'Stop'

$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
. "$Root\scripts\common.ps1"
. "$Root\scripts\env.ps1"

Assert-UnslothStopped -InstallationRoot $Root
Assert-SafeModelsRoot -InstallationRoot $Root -ModelsRoot $script:UnslothModels

Write-Host "`nUnsloth Studio native installation" -ForegroundColor Cyan
Write-Host "Root   : $Root"
Write-Host "Models : $script:UnslothModels"
Write-Host ''
Write-Host 'Repository scripts and LICENSE will be kept.'
Write-Host 'External model libraries are never deleted.'

$DefaultModels = Get-NormalizedPath (Join-Path $Root 'models')
$ActualModels = Get-NormalizedPath $script:UnslothModels

# Validate every managed removal target physically before deleting anything.
# The containment promise does not allow runtime/tools/cache/etc. to be
# junctions that redirect deletion outside the installation root.
$OwnedPaths = [ordered]@{
    runtime = "$Root\runtime"
    tools = "$Root\tools"
    python = "$Root\python"
    cache = "$Root\cache"
    logs = "$Root\logs"
    work = "$Root\work"
    forensic = "$Root\forensic"
}

foreach ($Relative in $OwnedPaths.Keys) {
    $Owned = $OwnedPaths[$Relative]
    if (Test-Path -LiteralPath $Owned) {
        Assert-ManagedChildPhysicalLocation `
            -InstallationRoot $Root `
            -Path $Owned `
            -RelativePath $Relative
    }

    if (Test-PathInsideOrEqual -Path $ActualModels -Parent $Owned -PhysicalWhenPossible) {
        throw "Refusing uninstall because ModelsRoot overlaps managed path '$Owned': $ActualModels"
    }
}

# Remove the uv receipt while tools still exist, and only when ownership is proven.
$UvReceipt = "$env:LOCALAPPDATA\uv\uv-receipt.json"
if (Test-Path -LiteralPath $UvReceipt -PathType Leaf) {
    try {
        $Receipt = Get-Content -LiteralPath $UvReceipt -Raw | ConvertFrom-Json
        $ExpectedPrefix = Get-NormalizedPath "$Root\tools\uv"

        if ($Receipt.install_prefix -and
            (Get-NormalizedPath ([string]$Receipt.install_prefix)).Equals(
                $ExpectedPrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
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

foreach ($Path in $OwnedPaths.Values) {
    if ((Test-Path -LiteralPath $Path) -and $PSCmdlet.ShouldProcess($Path, 'Remove managed installation data')) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

if ($RemoveModels) {
    if (-not $ActualModels.Equals($DefaultModels, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "ModelsRoot is external and will NOT be deleted: $ActualModels"
    } elseif ((Test-Path -LiteralPath $DefaultModels) -and $PSCmdlet.ShouldProcess($DefaultModels, 'Remove local models')) {
        # Assert-SafeModelsRoot already proved that the default path is not a
        # junction/alias before any managed tree was removed.
        Remove-Item -LiteralPath $DefaultModels -Recurse -Force
    }
} elseif (Test-Path -LiteralPath $ActualModels) {
    Write-Host "Models preserved: $ActualModels" -ForegroundColor Yellow
}

$Config = "$Root\config.psd1"
if ((Test-Path -LiteralPath $Config -PathType Leaf) -and $PSCmdlet.ShouldProcess($Config, 'Remove local installation configuration')) {
    Remove-Item -LiteralPath $Config -Force
}

Write-Host "`n=== UNINSTALL COMPLETE ===" -ForegroundColor Green
Write-Host 'Repository files were preserved.'
