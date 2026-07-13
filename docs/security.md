# Security

## Do Not Commit

Never commit:

- `.env` files with real values
- database dumps
- private keys
- TLS certificates
- SSH keys
- API tokens
- Keycloak admin passwords
- SMTP credentials

Use `.env.example` files with placeholders only.

## Docker Exposure

Production containers should bind to loopback:

```text
127.0.0.1:<port>
```

External access should go through Apache on `80/443`.

## Firewall

Do not install and enable `ufw` on an existing production host without checking
with systems/UTIC. Enabling a local firewall without explicit SSH rules can
break remote access.

If local firewall management is required, allow SSH before enabling it:

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## Tokens and Logs

When debugging authentication, never paste complete tokens into logs, issues, or
Slack. Print only a short prefix if needed:

```bash
echo "$TOKEN" | cut -c1-24
```

## SMTP

For production email delivery, request an institutional SMTP relay from systems.
Do not run unauthenticated public SMTP services from the application VM.

Required values are typically:

```text
SMTP host
SMTP port
TLS/STARTTLS requirement
username/password or relay allowlist
allowed sender address
```
