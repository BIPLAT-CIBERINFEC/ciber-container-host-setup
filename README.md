# CIBER Container Host Setup

Bootstrap and operating notes for CIBER/ISCIII virtual machines used to host
Docker-based web/API applications.

This repository is intentionally infrastructure-oriented and does not contain
project secrets, database dumps, TLS certificates, SSH keys, tokens, or
application-specific production environment files.

## Scope

The scripts and documentation prepare a minimal Linux VM for deployments such as:

- `pathocore-web`
- `pathocore-api`
- `mepram-omop-api`

The expected deployment model is:

- application repositories under `/opt/container_apps/<app_name>`
- Docker/container data under `/srv/containers`
- application and Apache logs under `/var/log/local/<app_name>`
- only Apache/reverse-proxy exposed publicly in production
- application containers bound to loopback in production

## Supported hosts

Primary target:

- Debian minimal VM

Also supported by the bootstrap script:

- Ubuntu LTS-like systems

Expected resources for PathoCore/MEPRAM-like deployments:

- 8 CPU cores
- 16 GB RAM
- `/opt`: at least 20 GB
- `/srv`: at least 40 GB
- SSH access with a sudo-capable deployment user
- outbound internet access for packages, GitHub, and container images

RHEL-like systems are not automated yet. See `docs/rhel-notes.md`.

## Repository Name

Recommended upstream name:

```text
ciber-container-host-setup
```

Suggested upstream:

```text
https://github.com/BIPLAT-CIBERINFEC/ciber-container-host-setup
```

Suggested fork:

```text
git@github.com:Daniel-VM/ciber-container-host-setup.git
```

## Quick Start

Run the host audit first. It is read-only and does not require sudo for most
checks:

```bash
bash scripts/check-host.sh
```

Preview the Debian bootstrap without applying changes:

```bash
bash scripts/bootstrap-debian-container-host.sh --dry-run
```

Apply the bootstrap on a fresh VM:

```bash
sudo DEPLOY_USER=bioinfoadm \
  bash scripts/bootstrap-debian-container-host.sh --apply
```

Optional app list:

```bash
sudo DEPLOY_USER=bioinfoadm \
  APPS="pathocore-web pathocore-api mepram-omop-api" \
  bash scripts/bootstrap-debian-container-host.sh --apply
```

## What the Bootstrap Does

The Debian bootstrap:

- installs base administration packages
- installs Apache
- installs Docker from the official Docker repository
- configures Docker storage under `/srv/containers/storage`
- configures containerd storage under `/srv/containers/containerd`
- creates the standard CIBER directory layout
- creates per-application bind, backup, and log folders
- adds the deployment user to the `docker` group
- enables common Apache reverse-proxy modules
- keeps production applications ready to bind internally to `127.0.0.1`

The script is idempotent and backs up existing Docker/containerd config files
before overwriting them.

## Installed Tools

The authoritative list of host-level tools installed by the bootstrap scripts is
maintained in:

```text
docs/tooling-inventory.md
```

Any pull request that adds, removes, or changes installed tools must update that
document or include an equivalent tools table in the PR description.

## Standard Directory Layout

```text
/opt/container_apps/<APP_NAME>
/var/log/local/<APP_NAME>/apps
/var/log/local/<APP_NAME>/apache
/srv/containers/backup/<APP_NAME>
/srv/containers/bind/<APP_NAME>
/srv/containers/shared
/srv/containers/storage
/srv/containers/containerd
```

See `docs/host-layout.md` for details.

## Network Model

Temporary development access may expose service ports directly only when agreed
with systems/UTIC.

Production should expose only:

```text
80/tcp
443/tcp
```

Application ports such as `3000`, `8000`, `8080`, and `8100` should remain
internal and be reached through Apache virtual hosts.

An example vhost file is available at:

```text
templates/apache/pathocore-mepram-vhosts.example.conf
```

See `docs/networking.md`.

## Security Notes

- Do not commit `.env`, database dumps, private keys, TLS certificates, or tokens.
- Do not print full tokens in logs or documentation.
- Keep Docker and application services bound to `127.0.0.1` in production.
- Use DNS + HTTPS + Apache reverse proxy for production exposure.
- Use SSH tunnels for temporary debugging when DNS/HTTPS is not ready.

See `docs/security.md`.

## Contributing

Pull requests use `.github/pull_request_template.md`. Contributors must declare
whether host-level tools changed. If a script installs a new package or enables a
new host service, the PR must include a table with the tool name, source, reason,
and operational impact.

## Validation

After setup:

```bash
docker --version
docker compose version
docker info | grep -E "Docker Root Dir|Storage Driver"
systemctl status docker --no-pager
systemctl status containerd --no-pager
apache2ctl -M | grep -E "proxy|headers|rewrite|ssl"
```

Then run:

```bash
bash scripts/check-host.sh
```

## Repository Status

This repository prepares the VM host only. It does not install application
repositories or configure application secrets. Those steps belong to each
application repository or to the production orchestrator repository.
