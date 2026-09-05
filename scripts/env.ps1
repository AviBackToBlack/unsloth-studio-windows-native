# Canonical process-local environment for Unsloth Studio on Windows.
# Dot-source from start.ps1 / update.ps1 / doctor.ps1 / model-sync.ps1.
# This file never writes persistent Windows environment variables.

$script:UnslothRoot = [System.IO.Path]::GetFullPath(
    (Split-Path -Parent $PSScriptRoot)
)

$script:UnslothConfigPath = Join-Path $script:UnslothRoot 'config.psd1'
$script:UnslothConfig = @{}

if (Test-Path -LiteralPath $script:UnslothConfigPath -PathType Leaf) {
    $script:UnslothConfig = Import-PowerShellDataFile -LiteralPath $script:UnslothConfigPath
}

$modelsSetting = $script:UnslothConfig.ModelsRoot
if ([string]::IsNullOrWhiteSpace($modelsSetting)) {
    $script:UnslothModels = Join-Path $script:UnslothRoot 'models'
} else {
    if (-not [System.IO.Path]::IsPathRooted($modelsSetting)) {
        throw "ModelsRoot in config.psd1 must be an absolute path: $modelsSetting"
    }
    $script:UnslothModels = [System.IO.Path]::GetFullPath($modelsSetting)
}

$script:UnslothPort = if ($null -ne $script:UnslothConfig.Port) {
    [int]$script:UnslothConfig.Port
} else {
    8888
}

if ($script:UnslothPort -lt 1 -or $script:UnslothPort -gt 65535) {
    throw "Invalid Port in config.psd1: $script:UnslothPort"
}

$script:UnslothUv = Join-Path $script:UnslothRoot 'tools\uv\uv.exe'
$script:UnslothPythonState = Join-Path $script:UnslothRoot 'forensic\managed-python.json'
$script:UnslothBasePython = $null

if (Test-Path -LiteralPath $script:UnslothPythonState -PathType Leaf) {
    try {
        $pythonState = Get-Content -LiteralPath $script:UnslothPythonState -Raw | ConvertFrom-Json
        if ($pythonState.executable) {
            $candidate = [System.IO.Path]::GetFullPath([string]$pythonState.executable)
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $script:UnslothBasePython = $candidate
            }
        }
    } catch {}
}

if (-not $script:UnslothBasePython -and (Test-Path -LiteralPath $script:UnslothUv -PathType Leaf)) {
    try {
        $candidate = (& $script:UnslothUv python find --managed-python 3.13 2>$null).Trim()
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $script:UnslothBasePython = [System.IO.Path]::GetFullPath($candidate)
        }
    } catch {}
}

$script:UnslothStudioPython = Join-Path $script:UnslothRoot 'runtime\unsloth_studio\Scripts\python.exe'

# Unsloth
$env:UNSLOTH_NATIVE_ROOT = $script:UnslothRoot
$env:UNSLOTH_MODELS_ROOT = $script:UnslothModels
$env:UNSLOTH_STUDIO_HOME = Join-Path $script:UnslothRoot 'runtime'
$env:UNSLOTH_LLAMA_CPP_PATH = Join-Path $script:UnslothRoot 'runtime\llama.cpp'
$env:UNSLOTH_PYTHON = '3.13'
$env:UNSLOTH_SKIP_AUTOSTART = '1'

# Safety rail: use the managed CUDA prebuilt path and never deliberately
# force a local/source llama.cpp build.
$env:UNSLOTH_LLAMA_CPP_BACKEND = 'cuda'
$env:UNSLOTH_LLAMA_TAG = 'latest'

@(
    'UNSLOTH_LLAMA_FORCE_COMPILE'
    'UNSLOTH_LLAMA_FORCE_COMPILE_REF'
    'UNSLOTH_LLAMA_PR'
    'UNSLOTH_LLAMA_PR_FORCE'
    'UNSLOTH_LOCAL_LLAMA_CPP_DIR'
    'UNSLOTH_LLAMA_FORCE_VULKAN'
) | ForEach-Object {
    Remove-Item "Env:$_" -ErrorAction SilentlyContinue
}

# uv
$env:UV_INSTALL_DIR = Join-Path $script:UnslothRoot 'tools\uv'
$env:UV_NO_MODIFY_PATH = '1'
$env:UV_CACHE_DIR = Join-Path $script:UnslothRoot 'cache\uv'
$env:UV_PYTHON_INSTALL_DIR = Join-Path $script:UnslothRoot 'python'
$env:UV_PYTHON_INSTALL_BIN = '0'
$env:UV_TOOL_DIR = Join-Path $script:UnslothRoot 'tools\uv-tools'
$env:UV_TOOL_BIN_DIR = Join-Path $script:UnslothRoot 'tools\uv-bin'

# Python / ML caches
$env:HF_HOME = Join-Path $script:UnslothRoot 'cache\huggingface'
$env:HF_HUB_CACHE = Join-Path $script:UnslothRoot 'cache\huggingface\hub'
$env:HF_XET_CACHE = Join-Path $script:UnslothRoot 'cache\huggingface\xet'
$env:HF_XET_HIGH_PERFORMANCE = '1'
$env:TORCH_HOME = Join-Path $script:UnslothRoot 'cache\torch'
$env:TORCHINDUCTOR_CACHE_DIR = Join-Path $script:UnslothRoot 'runtime\TORCHINDUCTOR_CACHE_DIR'
$env:PIP_CACHE_DIR = Join-Path $script:UnslothRoot 'cache\pip'
$env:TEMP = Join-Path $script:UnslothRoot 'cache\temp'
$env:TMP = Join-Path $script:UnslothRoot 'cache\temp'
$env:PYTHONNOUSERSITE = '1'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

# Process-local PATH only
$localEntries = @(
    (Join-Path $script:UnslothRoot 'tools\uv')
)

if ($script:UnslothBasePython) {
    $localEntries += Split-Path -Parent $script:UnslothBasePython
}

$currentEntries = @(
    $env:PATH -split ';' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

$seen = @{}
$dedupedEntries = foreach ($entry in @($localEntries + $currentEntries)) {
    $key = $entry.Trim().Trim('"').TrimEnd('\').ToLowerInvariant()
    if ($key -and -not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        $entry
    }
}

$env:PATH = $dedupedEntries -join ';'
