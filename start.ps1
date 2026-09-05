$ErrorActionPreference = 'Stop'

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
Write-Host "  URL     : http://127.0.0.1:$($script:UnslothPort)"
Write-Host ""

# Keep the primary listener loopback-only. LAN access, when desired, should
# be enabled through Unsloth Studio's own Remote & LAN settings.
& $Studio studio -H 127.0.0.1 -p $script:UnslothPort
exit $LASTEXITCODE
