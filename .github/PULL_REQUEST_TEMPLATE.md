## Summary

Describe the change and why it is needed.

## Validation

- [ ] PowerShell parsing/static analysis passes.
- [ ] No credentials, runtime state, models, caches, or databases were committed.
- [ ] Process-local environment isolation is preserved.
- [ ] Model sync remains dry-run by default unless this PR explicitly changes that contract.
- [ ] Any CUDA/backend/update safety impact is documented below.

## Runtime/GPU impact

Describe trusted-machine acceptance performed, if applicable. Public PR CI intentionally does not execute the managed GPU runtime.
