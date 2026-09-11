# Contributing

Thanks for contributing to `unsloth-studio-windows-native`.

## Scope

Keep changes focused on the native-Windows managed-runtime scripts and their documentation. Do not introduce persistent host environment changes, credential exposure, or source-build fallbacks as convenience shortcuts.

## Before opening a pull request

- Run the repository's PowerShell parse/static checks.
- Keep model synchronization dry-run by default.
- Preserve process-local environment isolation.
- Do not commit runtime state, models, caches, databases, tokens, or other credentials.
- Explain any change to CUDA/backend/update/model-sync safety behavior in the PR body.

GPU/runtime acceptance requires a trusted Windows machine with the managed installation and is intentionally separate from public PR CI.

## Security issues

Do not open public issues for suspected vulnerabilities. Follow `SECURITY.md` or use GitHub private vulnerability reporting when available.
