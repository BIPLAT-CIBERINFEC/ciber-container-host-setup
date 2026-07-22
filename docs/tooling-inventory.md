# Tooling Inventory

This document tracks host-level tools installed by the bootstrap scripts.

Every pull request that adds, removes, or changes installed tools must update
this table or include an equivalent table in the PR description.

## Debian/Ubuntu Bootstrap Tools

Installed by:

```text
scripts/bootstrap-debian-container-host.sh
```

| Tool / Package | Source | Purpose | Installed by default | Notes |
|---|---|---|---|---|
| `ca-certificates` | OS package repository | TLS certificate trust store for HTTPS package downloads and API checks | Yes | Required before adding external repositories |
| `curl` | OS package repository | HTTP checks, repository bootstrap, diagnostics | Yes | Used by scripts and validation commands |
| `gnupg` | OS package repository | GPG key handling for external repositories | Yes | Required for Docker repository key setup |
| `lsb-release` | OS package repository | OS metadata helper | Yes | Useful for diagnostics and repository setup |
| `git` | OS package repository | Clone and update application repositories | Yes | Required for deployment workflows |
| `wget` | OS package repository | Alternative download tool | Yes | Operational convenience |
| `jq` | OS package repository | JSON inspection in shell workflows | Yes | Useful for API and Keycloak checks |
| `unzip` | OS package repository | Archive extraction | Yes | Operational convenience |
| `rsync` | OS package repository | File synchronization and deployment helpers | Yes | Useful for controlled file copies |
| `vim` | OS package repository | Terminal editing | Yes | Operational convenience |
| `htop` | OS package repository | Interactive process/resource inspection | Yes | Operational convenience |
| `tree` | OS package repository | Directory layout inspection | Yes | Useful for validating host structure |
| `net-tools` | OS package repository | Legacy network commands such as `ifconfig` | Yes | Kept for operator convenience; prefer `ip` commands for new documentation |
| `apache2` | OS package repository | Reverse proxy for public HTTP/HTTPS access | Yes | Production entrypoint before application containers |
| `docker-ce` | Official Docker repository | Docker Engine daemon | Yes | Docker data root is configured under `/srv/containers/storage` |
| `docker-ce-cli` | Official Docker repository | Docker CLI | Yes | Required for local Docker operations |
| `containerd.io` | Official Docker repository | Container runtime | Yes | Root configured under `/srv/containers/containerd` |
| `docker-buildx-plugin` | Official Docker repository | Docker Buildx support | Yes | Required for modern image builds |
| `docker-compose-plugin` | Official Docker repository | `docker compose` subcommand | Yes | Required for Compose-based deployments |

## Apache Modules

Enabled by:

```text
scripts/bootstrap-debian-container-host.sh
```

| Module | Purpose | Enabled by default | Notes |
|---|---|---|---|
| `proxy` | Core Apache reverse-proxy support | Yes | Required for all proxied services |
| `proxy_http` | HTTP reverse-proxy backend support | Yes | Required for Docker services on local HTTP ports |
| `headers` | Forwarded headers and proxy metadata | Yes | Required for `X-Forwarded-*` handling |
| `rewrite` | URL rewriting support | Yes | Useful for future routing rules |
| `ssl` | HTTPS/TLS virtual hosts | Yes | Required once certificates are available |

## Contribution Rule

When changing installed tools, add a table like this to the PR description if
the inventory update is not enough by itself:

| Change | Tool / Package | Source | Reason | Operational impact |
|---|---|---|---|---|
| Add / Remove / Change | `package-name` | OS / Docker / External | Why this is needed | Ports, services, storage, security, or maintenance impact |

If no tooling changes are introduced, explicitly write:

```text
No host-level tools added, removed, or changed.
```
