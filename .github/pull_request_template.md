## Summary

<!-- Briefly describe what this PR changes. -->

## Scope

<!-- Select all that apply. -->

- [ ] Documentation only
- [ ] Host bootstrap script
- [ ] Host audit/check script
- [ ] Directory layout or permissions
- [ ] Docker/containerd configuration
- [ ] Backup/cron configuration
- [ ] Other:

## Tooling Changes

Every PR that changes installed host-level tools must update
`docs/tooling-inventory.md` or include the table below.

If this PR does not add, remove, or change installed tools, write:

```text
No host-level tools added, removed, or changed.
```

| Change | Tool / Package | Source | Reason | Operational impact |
|---|---|---|---|---|
| Add / Remove / Change | `package-name` | OS / Docker / External | Why this is needed | Services, storage, security, or maintenance impact |

## Validation

<!-- Paste relevant validation commands. Do not paste secrets. -->

- [ ] `bash -n scripts/check-host.sh scripts/bootstrap-debian-container-host.sh`
- [ ] `bash scripts/bootstrap-debian-container-host.sh --dry-run`
- [ ] Documentation reviewed for secrets

## Security Checklist

- [ ] No `.env` files with real values committed
- [ ] No passwords, tokens, private keys, certificates, or database dumps committed
- [ ] No full tokens printed in docs or examples
- [ ] New host services are documented, if applicable
