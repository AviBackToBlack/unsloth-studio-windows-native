# Unsloth Studio — Windows Native

Native-Windows operator scripts for a managed Unsloth Studio installation rooted at `D:\AI\Unsloth`, with models stored under `D:\AI\Models`.

The repository intentionally keeps the Windows environment isolated: `scripts/env.ps1` builds a process-local environment for the managed runtime and does not persistently modify the user or machine `PATH`.

## Layout

- `start.ps1` — starts the managed Unsloth Studio on `http://localhost:8888`.
- `doctor.ps1` — reports package/GPU/runtime/database/credential/isolation health.
- `update.ps1` — stops on an active Studio instance, snapshots important state, runs the official Studio updater, then validates CUDA and database state.
- `model-sync.ps1` — safely synchronizes Hugging Face model content into the managed model tree. It is dry-run by default; `-Apply` is required to download.
- `scripts/env.ps1` — canonical process-local paths, cache locations, Python/uv settings, and CUDA backend safety rails.

## Assumptions

The current scripts target the managed layout below:

```text
D:\AI\Unsloth
D:\AI\Models
```

They expect a previously provisioned Unsloth Studio runtime. This repository does not currently contain a generic installer and CI does not pretend to provide a CUDA/GPU acceptance environment.

## Common operations

Start Studio:

```powershell
.\start.ps1
```

Inspect the installation:

```powershell
.\doctor.ps1
```

Update a stopped Studio installation:

```powershell
.\update.ps1
```

Preview a filtered Hugging Face model sync:

```powershell
.\model-sync.ps1 owner/model -Include '*.safetensors','*.json'
```

Apply the same sync only after reviewing the dry run:

```powershell
.\model-sync.ps1 owner/model -Include '*.safetensors','*.json' -Apply
```

## Safety model

- `model-sync.ps1` obtains the saved Hugging Face token through Studio's credential storage rather than exporting the token into the process environment.
- Temporary sync parameters are removed in a `finally` block.
- `update.ps1` snapshots Studio/auth databases before updating and validates CUDA/database state afterwards.
- Explicit CUDA/backend settings are treated as safety rails; do not silently replace them with source-build fallbacks.
- Runtime files, models, caches, credentials, and databases do not belong in this repository.

## CI scope

Public pull-request CI performs source-level validation only: PowerShell parsing, static analysis, and GitHub Actions security analysis. GPU/CUDA/runtime acceptance belongs in a trusted Windows environment with the managed installation present; public PR code must not be executed on a home/self-hosted GPU runner.

## License

See [LICENSE](LICENSE).
