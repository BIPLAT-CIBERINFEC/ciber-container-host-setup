# Operations

## Initial VM Checklist

```bash
hostnamectl
df -h
free -h
lscpu
ip a
ip route
getent hosts github.com
curl -I https://github.com
curl -I https://registry-1.docker.io
```

## After Bootstrap

```bash
docker --version
docker compose version
docker info | grep -E "Docker Root Dir|Storage Driver"
systemctl status docker --no-pager
systemctl status containerd --no-pager
apache2ctl -M | grep -E "proxy|headers|rewrite|ssl"
```

## Log Review

```bash
sudo du -hxd1 /var | sort -h
sudo du -hxd1 /srv | sort -h
sudo journalctl -u docker --since "1 hour ago" --no-pager
sudo journalctl -u containerd --since "1 hour ago" --no-pager
```

## Apache Config Test

```bash
sudo apache2ctl configtest
sudo systemctl reload apache2
```

## Docker Cleanup

Use only after confirming that no needed image/container/volume will be removed:

```bash
docker system df
docker ps -a
docker volume ls
```

Avoid destructive cleanup commands on shared production hosts unless there is a
specific maintenance window.

## Backup Checks

Run a manual dry-run:

```bash
sudo bash scripts/backup-container-host.sh \
  --config /etc/ciber-container-backup.env \
  --dry-run
```

Run a real backup without waiting for the nightly cron:

```bash
sudo bash scripts/backup-container-host.sh \
  --config /etc/ciber-container-backup.env
```

Check backup logs and files:

```bash
sudo tail -n 100 /var/log/local/container-backup/container-backup-$(date +%Y%m%d).log
sudo find /srv/containers/backup/host -maxdepth 3 -type f | sort
```

See `docs/backups.md` for configuration and restore notes.
