$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
. "$Root\scripts\env.ps1"

$InstallState = Join-Path $Root 'forensic\install-state.json'
$Studio = Join-Path $Root 'runtime\bin\unsloth.cmd'

if (-not (Test-Path -LiteralPath $InstallState -PathType Leaf)) {
    throw "Unsloth Studio installation is not complete. Run .\install.ps1 or .\install.ps1 -Repair first."
}

if (-not (Test-Path -LiteralPath $Studio -PathType Leaf)) {
    throw "Unsloth Studio is not installed. Run .\install.ps1 first."
}

$OperationLock = Enter-UnslothOperationLock -InstallationRoot $Root -Operation 'start'
try {
    Write-Host "Unsloth Studio" -ForegroundColor Cyan
    Write-Host "  Root    : $Root"
    Write-Host "  Runtime : $env:UNSLOTH_STUDIO_HOME"
    Write-Host "  Models  : $script:UnslothModels"
    Write-Host "  GPU     : CUDA"
    Write-Host "  URL     : http://127.0.0.1:$($script:UnslothPort)"
    Write-Host ""

    # Keep the primary listener loopback-only. LAN access, when desired, should
    # be enabled through Unsloth Studio's own Remote & LAN settings.
    & $Studio studio -H 127.0.0.1 -p $script:UnslothPort
    $StudioExit = $LASTEXITCODE
} finally {
    Exit-UnslothOperationLock -Lock $OperationLock
}

exit $StudioExit
