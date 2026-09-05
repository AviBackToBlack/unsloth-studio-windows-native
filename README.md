# Unsloth Studio Windows Native

A small, unofficial wrapper around the **official Unsloth Studio Windows installer** that keeps the managed runtime under one directory.

The goal is simple: choose a folder for Unsloth Studio and keep its managed Python, uv, Node.js, llama.cpp, whisper.cpp, caches, application state and logs there instead of spreading them across the user profile and persistent system PATH.

> [!IMPORTANT]
> This is a community project and is not affiliated with or endorsed by Unsloth AI.
> It downloads and runs the current official Unsloth Studio installer from `https://unsloth.ai/install.ps1`.

## Layout

After installation, the repository directory becomes the installation root:

```text
unsloth-studio-windows-native/
├── install.ps1
├── start.ps1
├── update.ps1
├── doctor.ps1
├── model-sync.ps1
├── uninstall.ps1
├── config.psd1              # generated locally; ignored by Git
├── scripts/
│   └── env.ps1
├── runtime/                 # Unsloth Studio, venv, Node, llama.cpp, state
├── python/                  # uv-managed CPython
├── tools/                   # uv
├── cache/                   # HF, Xet, Torch, pip, uv, temp
├── logs/
├── forensic/
├── work/
└── models/                  # default model library; optional
```

Generated/runtime directories are ignored by Git.

## Host prerequisites

v0.1 deliberately **does not install or modify system prerequisites**. Install these first:

- Windows x64
- PowerShell 7+
- NVIDIA GPU with a working NVIDIA driver (`nvidia-smi.exe`)
- Git for Windows
- Microsoft Visual C++ 2015-2022 Redistributable, x64
- Windows long path support enabled (`LongPathsEnabled = 1`)

You do **not** need to preinstall:

- Python
- Node.js / npm / Bun
- CUDA Toolkit / `nvcc`
- CMake
- Visual Studio Build Tools

The setup configures Unsloth's managed CUDA/prebuilt path and does not provision a source-build toolchain.

## Install

Clone the repository directly into the directory you want to use as the installation root:

```powershell
git clone https://github.com/AviBackToBlack/unsloth-studio-windows-native.git D:\AI\Unsloth
cd D:\AI\Unsloth
pwsh .\install.ps1
```

By default, models live under:

```text
<installation root>\models
```

To use an existing model library:

```powershell
pwsh .\install.ps1 -ModelsRoot 'D:\AI\Models'
```

`install.ps1`:

1. verifies host prerequisites;
2. records a small pre-install forensic baseline;
3. installs the latest uv into `<root>\tools\uv`;
4. installs managed CPython 3.13 into `<root>\python`;
5. downloads the current official Unsloth installer and records its SHA-256;
6. runs it with a process-local containment environment;
7. validates CUDA, core managed components, persistent PATH and build-tool leakage.

## Start

```powershell
pwsh .\start.ps1
```

Default listener:

```text
http://127.0.0.1:8888
```

Edit the generated `config.psd1` to change the port, bind host or model library.

`start.ps1` intentionally does **not** auto-update the installation.

## Update

Stop Studio first, then:

```powershell
pwsh .\update.ps1
```

The updater uses the official:

```text
unsloth studio update
```

Before updating it backs up `studio.db` and `auth.db`. Afterward it validates CUDA, database integrity, persistent PATH and unexpected CMake/`nvcc` appearance.

## Health check

```powershell
pwsh .\doctor.ps1
```

The doctor reports:

- Unsloth / PyTorch versions
- CUDA device and capability
- Studio/auth database integrity
- saved Hugging Face credential status
- model scan folders
- managed component presence
- persistent PATH isolation
- external footprint
- Studio health endpoint

It exits with a non-zero status when a core health check fails.

## Hugging Face model sync

Sign in to Hugging Face from Unsloth Studio first. `model-sync.ps1` reuses the token stored by Studio; it never prints the token.

Dry-run a whole repository:

```powershell
pwsh .\model-sync.ps1 'unsloth/Qwen3.8-27B-NVFP4' -Mode All
```

Download it:

```powershell
pwsh .\model-sync.ps1 'unsloth/Qwen3.8-27B-NVFP4' -Mode All -Apply
```

Or select files:

```powershell
pwsh .\model-sync.ps1 'org/model-GGUF' `
    -Include '*Q5_K_M.gguf','*.json','tokenizer*'
```

Downloads go directly to:

```text
<ModelsRoot>\huggingface\<org>\<repo>
```

The Hugging Face `local_dir` metadata remains alongside the model; the script does not create a second full model snapshot in the project cache.

## Uninstall

```powershell
pwsh .\uninstall.ps1
```

The script removes managed installation data but preserves:

- repository files;
- models by default;
- any external `ModelsRoot`.

To also delete the default local `<root>\models` directory:

```powershell
pwsh .\uninstall.ps1 -RemoveModels
```

An external model library is never deleted, even with `-RemoveModels`.

## Isolation model

All containment variables are set only in the PowerShell process tree used to install, start, update or maintain Studio.

The project does not intentionally add its directories to persistent User or Machine `PATH`.

| Component | Location |
|---|---|
| Unsloth Studio | `<root>\runtime` |
| Python | `<root>\python` |
| uv | `<root>\tools\uv` |
| uv cache | `<root>\cache\uv` |
| Hugging Face cache | `<root>\cache\huggingface` |
| Torch cache | `<root>\cache\torch` |
| pip cache | `<root>\cache\pip` |
| temp | `<root>\cache\temp` |
| logs | `<root>\logs` |

### Known external footprint

The official uv installer currently writes:

```text
%LOCALAPPDATA%\uv\uv-receipt.json
```

even when `UV_INSTALL_DIR` points inside the project root. This file is small and contains installer metadata, not Python packages or caches.

`uninstall.ps1` removes it **only when its `install_prefix` proves that it belongs to this installation**.

## License

The wrapper scripts in this repository are MIT licensed. Unsloth Studio and downloaded third-party components retain their own licenses.
