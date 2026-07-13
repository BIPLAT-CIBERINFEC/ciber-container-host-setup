# Networking

## Production Model

Production should expose only:

```text
80/tcp
443/tcp
```

Apache should act as the public reverse proxy and forward requests to local
container ports bound to `127.0.0.1`.

Recommended DNS model:

```text
mepram-datahub.<domain>       -> web frontend
api-pathocore.<domain>        -> PathoCore API
keycloak-pathocore.<domain>   -> Keycloak
api-mepram-omop.<domain>      -> MEPRAM OMOP API
```

In development/preproduction, use the institution development domain if
available. For example:

```text
mepram-datahub.<dev-domain>
api-pathocore.<dev-domain>
keycloak-pathocore.<dev-domain>
api-mepram-omop.<dev-domain>
```

If development and production share a DNS domain, use a clear suffix such as
`-dev` for development names.

## Internal Ports

Common internal service ports:

```text
3000  pathocore-web
8000  pathocore-api
8080  Keycloak
8100  mepram-omop-api
```

These should normally remain bound to `127.0.0.1` in production.

## Temporary Debugging

When DNS/HTTPS is not ready, prefer SSH tunnels over opening public ports:

```bash
ssh -N \
  -L 3000:127.0.0.1:3000 \
  -L 8000:127.0.0.1:8000 \
  -L 8080:127.0.0.1:8080 \
  -L 8100:127.0.0.1:8100 \
  <user>@<vm-ip>
```

Temporary direct port exposure should be agreed with systems/UTIC and restricted
to authorized source IPs when possible.

## Connectivity Checks

From the VM:

```bash
curl -I https://github.com
curl -I https://registry-1.docker.io
getent hosts github.com
ip route
ss -ltnp
```

From a workstation:

```bash
nc -vz <vm-ip> 22
nc -vz <vm-ip> 80
nc -vz <vm-ip> 443
```
