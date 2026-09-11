# AGENTS.md

Repository-wide instructions for coding agents and automation.

## Project intent

This repository contains operator scripts for a native Windows Unsloth Studio installation. Preserve the managed, isolated layout and its safety rails; do not turn maintenance work into an installer/runtime redesign unless explicitly requested.

## Critical invariants

- Canonical managed root is currently `D:\AI\Unsloth`; model storage is `D:\AI\Models`.
- `scripts/env.ps1` configures process-local environment state. Do not persistently modify user/machine PATH or Python settings as a shortcut.
- Keep runtime, models, caches, databases, and credentials out of Git.
- Keep the explicit CUDA backend/source-build safety behavior intact unless a task intentionally changes that policy.
- `model-sync.ps1` must remain dry-run by default. Downloads require explicit `-Apply`.
- Do not expose the saved Hugging Face token through environment variables, logs, command lines, or committed files.
- Preserve cleanup of temporary model-sync environment variables.
- `update.ps1` must continue to protect state before update and validate the resulting CUDA/database state.

## Validation

Public PR CI is source-level only. Run PowerShell parse/static checks and GitHub Actions security checks.

Do not execute untrusted public PR code on a home/self-hosted GPU runner. GPU/runtime acceptance belongs in a trusted Windows environment with the managed installation present.

## Governance

Keep GitHub Actions pinned to full commit SHAs with readable version comments. Do not weaken CI/security/governance policy without an explicit task and documented reason.
