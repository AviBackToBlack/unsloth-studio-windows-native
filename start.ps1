$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = $PSScriptRoot
. "$Root\scripts\env.ps1"

$Studio = Join-Path $Root 'runtime\bin\unsloth.cmd'

if (-not (Test-Path -LiteralPath $Studio -PathType Leaf)) {
    throw "Unsloth Studio is not installed. Run .\install.ps1 first."
}

Write-Host "Unsloth Studio" -ForegroundColor Cyan
Write-Host "  Root    : $Root"
Write-Host "  Runtime : $env:UNSLOTH_STUDIO_HOME"
Write-Host "  Models  : $script:UnslothModels"
Write-Host "  GPU     : CUDA"
Write-Host "  URL     : http://$($script:UnslothBindHost):$($script:UnslothPort)"
Write-Host ""

& $Studio studio -H $script:UnslothBindHost -p $script:UnslothPort
exit $LASTEXITCODE
