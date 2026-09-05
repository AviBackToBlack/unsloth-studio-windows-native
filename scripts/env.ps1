# Canonical process-local environment for native Windows Unsloth Studio.
# Dot-source this file from start.ps1 / update.ps1 / maintenance scripts.
# Nothing here modifies persistent Windows environment variables.

$script:UnslothRoot = 'D:\AI\Unsloth'

$script:UnslothUv =
    "$script:UnslothRoot\tools\uv\uv.exe"

$script:UnslothBasePython =
    "$script:UnslothRoot\python\cpython-3.13-windows-x86_64-none\python.exe"

$script:UnslothStudioPython =
    "$script:UnslothRoot\runtime\unsloth_studio\Scripts\python.exe"

# --------------------------------------------------------------------
# Unsloth
# --------------------------------------------------------------------

$env:UNSLOTH_STUDIO_HOME =
    "$script:UnslothRoot\runtime"

$env:UNSLOTH_LLAMA_CPP_PATH =
    "$script:UnslothRoot\runtime\llama.cpp"

$script:UnslothModels = 'D:\AI\Models'

$env:HF_XET_HIGH_PERFORMANCE = '1'

$env:UNSLOTH_PYTHON = '3.13'

# Installer must not launch Studio automatically.
$env:UNSLOTH_SKIP_AUTOSTART = '1'

# Explicit CUDA backend is also our safety rail:
# current setup.ps1 refuses a source build when an explicit backend would
# require one; matching prebuilt or fail.
$env:UNSLOTH_LLAMA_CPP_BACKEND = 'cuda'
$env:UNSLOTH_LLAMA_TAG = 'latest'

# Remove knobs that can deliberately force source builds or point at
# user-supplied llama.cpp trees.
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

# --------------------------------------------------------------------
# uv
# --------------------------------------------------------------------

$env:UV_INSTALL_DIR =
    "$script:UnslothRoot\tools\uv"

$env:UV_NO_MODIFY_PATH = '1'

$env:UV_CACHE_DIR =
    "$script:UnslothRoot\cache\uv"

$env:UV_PYTHON_INSTALL_DIR =
    "$script:UnslothRoot\python"

# No ~/.local/bin Python shims.
$env:UV_PYTHON_INSTALL_BIN = '0'

# If uv tools ever get used, keep them on D: too.
$env:UV_TOOL_DIR =
    "$script:UnslothRoot\tools\uv-tools"

$env:UV_TOOL_BIN_DIR =
    "$script:UnslothRoot\tools\uv-bin"

# --------------------------------------------------------------------
# Python / ML caches
# --------------------------------------------------------------------

$env:HF_HOME =
    "$script:UnslothRoot\cache\huggingface"

$env:HF_HUB_CACHE =
    "$script:UnslothRoot\cache\huggingface\hub"

$env:HF_XET_CACHE =
    "$script:UnslothRoot\cache\huggingface\xet"

$env:TORCH_HOME =
    "$script:UnslothRoot\cache\torch"

$env:TORCHINDUCTOR_CACHE_DIR =
    "$script:UnslothRoot\runtime\TORCHINDUCTOR_CACHE_DIR"

$env:PIP_CACHE_DIR =
    "$script:UnslothRoot\cache\pip"

$env:TEMP =
    "$script:UnslothRoot\cache\temp"

$env:TMP =
    "$script:UnslothRoot\cache\temp"

$env:PYTHONNOUSERSITE = '1'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

# --------------------------------------------------------------------
# Process-local PATH only
# --------------------------------------------------------------------

$localEntries = @(
    "$script:UnslothRoot\tools\uv"
    "$script:UnslothRoot\python\cpython-3.13-windows-x86_64-none"
)

$currentEntries = @(
    $env:PATH -split ';' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

$all = @($localEntries + $currentEntries)

$seen = @{}
$dedupedEntries = foreach ($entry in $all) {
    $key = $entry.Trim().Trim('"').TrimEnd('\').ToLowerInvariant()

    if ($key -and -not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        $entry
    }
}

$env:PATH = $dedupedEntries -join ';'
