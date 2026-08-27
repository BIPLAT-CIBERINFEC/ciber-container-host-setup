# SMTP Relay

This repository can prepare a host-level SMTP relay for application containers.
The applications should only know where the local relay is; institutional SMTP
details stay in the host setup.

Supported modes:

| Mode | What it does | When to use |
|---|---|---|
| `host-postfix` | Installs and configures Postfix directly on the VM | Preferred when the VM can run host services |
| `container-postfix` | Creates a dedicated Postfix relay container under `/srv/containers/shared/smtp-relay` | Useful when host packages should stay minimal |

In both modes the application flow is:

```text
application container -> local SMTP relay -> institutional SMTP server
```

## Configure

Create the local configuration file:

```bash
sudo cp templates/env/ciber-smtp-relay.example.env /etc/ciber-smtp-relay.env
sudo chmod 0600 /etc/ciber-smtp-relay.env
sudo vim /etc/ciber-smtp-relay.env
```

Set at least:

```env
SMTP_RELAY_UPSTREAM_HOST="ciberisciii-es.mail.protection.outlook.com"
SMTP_RELAY_UPSTREAM_PORT="25"
SMTP_RELAY_TLS_SECURITY_LEVEL="may"
SMTP_DEFAULT_FROM_EMAIL="bioinformatica.infec@ciberisciii.es"
```

If the institution requires SMTP authentication, set:

```env
SMTP_RELAY_UPSTREAM_AUTH="true"
SMTP_RELAY_UPSTREAM_USER="application@example.org"
SMTP_RELAY_UPSTREAM_PASSWORD="change_me"
```

If the institution allows relay by IP, keep user and password empty.

## Host Postfix Mode

Preview:

```bash
sudo bash scripts/setup-smtp-relay.sh \
  --config /etc/ciber-smtp-relay.env \
  --mode host-postfix \
  --dry-run
```

Apply:

```bash
sudo bash scripts/setup-smtp-relay.sh \
  --config /etc/ciber-smtp-relay.env \
  --mode host-postfix \
  --apply
```

With `SMTP_RELAY_INET_INTERFACES="auto"` and `SMTP_RELAY_MYNETWORKS="auto"`,
the script allows loopback and current Docker network gateways/subnets.

## Container Postfix Mode

Preview:

```bash
sudo bash scripts/setup-smtp-relay.sh \
  --config /etc/ciber-smtp-relay.env \
  --mode container-postfix \
  --dry-run
```

Apply:

```bash
sudo bash scripts/setup-smtp-relay.sh \
  --config /etc/ciber-smtp-relay.env \
  --mode container-postfix \
  --apply
```

By default the container publishes port `25` on `0.0.0.0` so other application
containers can reach it through the host gateway. Restrict inbound access at the
host firewall when the VM is not on a trusted network, or override:

```env
SMTP_RELAY_BIND_HOST="127.0.0.1"
SMTP_RELAY_BIND_PORT="2525"
SMTP_APP_PORT="2525"
```

When `SMTP_RELAY_INET_INTERFACES` or `SMTP_RELAY_MYNETWORKS` are set to `auto`,
container mode renders them as container-safe Postfix values.

## Application Variables

Print the values that application/orchestrator env files should use:

```bash
bash scripts/setup-smtp-relay.sh \
  --config /etc/ciber-smtp-relay.env \
  --print-app-env
```

Typical Django settings:

```env
EMAIL_HOST=host.docker.internal
EMAIL_PORT=25
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
EMAIL_USE_TLS=false
DEFAULT_FROM_EMAIL=bioinformatica.infec@ciberisciii.es
```

Typical Keycloak SMTP settings:

```text
Host: host.docker.internal
Port: 25
Enable SSL: false
Enable StartTLS: false
Authentication: disabled
From: bioinformatica.infec@ciberisciii.es
```

If `host.docker.internal` is not available in a Linux container, add the Docker
Compose mapping `host.docker.internal:host-gateway` in the application stack or
use the Docker bridge gateway IP directly.

## Validate

Check host Postfix:

```bash
sudo postconf -n | grep -E 'relayhost|inet_interfaces|inet_protocols|mynetworks|smtp_tls_security_level|smtp_sasl_auth_enable'
sudo systemctl status postfix --no-pager
```

Check container Postfix:

```bash
docker logs --tail 100 ciber-smtp-relay
docker exec ciber-smtp-relay postconf -n | grep -E 'relayhost|inet_protocols|mynetworks|smtp_tls_security_level|smtp_sasl_auth_enable'
docker exec ciber-smtp-relay postqueue -p
```

Check connectivity from an application container:

```bash
docker exec <app-container> bash -lc \
  'timeout 5 bash -c "</dev/tcp/host.docker.internal/25" && echo OK || echo FAIL'
```
