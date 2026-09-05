$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot

. "$Root\scripts\env.ps1"

$Studio = "$Root\runtime\bin\unsloth.cmd"

if (-not (Test-Path -LiteralPath $Studio -PathType Leaf)) {
    throw "Unsloth Studio launcher not found: $Studio"
}

Write-Host "Unsloth Studio" -ForegroundColor Cyan
Write-Host "  Runtime : $env:UNSLOTH_STUDIO_HOME"
Write-Host "  Models  : $script:UnslothModels"
Write-Host "  GPU     : CUDA"
Write-Host "  URL     : http://localhost:8888"
Write-Host ""

& $Studio studio -p 8888

exit $LASTEXITCODE
