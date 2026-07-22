# Backups

This repository provides a host-level backup policy for CIBER container VMs.

The backup script is intentionally local and conservative. It does not require
external backup infrastructure and does not commit secrets.

## Scope

The backup job covers:

- bind mounts under `/srv/containers/bind`
- Docker named volumes using their local mountpoints
- Docker images, saved once per immutable image ID
- configured MySQL/MariaDB databases using logical dumps
- execution logs under `/var/log/local/container-backup`

Database dumps are the primary restore source for MySQL/MariaDB data. Volume
snapshots are still useful for bind-mounted files, uploaded documents, static
state, and secondary inspection, but live database volumes should not be the only
database recovery mechanism.

## Configuration

Create a host-local config from the template:

```bash
sudo cp templates/env/ciber-container-backup.example.env /etc/ciber-container-backup.env
sudo chmod 0600 /etc/ciber-container-backup.env
sudo vim /etc/ciber-container-backup.env
```

Do not commit the edited config file. It may contain database passwords.

Each database entry uses this format:

```text
backup_name|container_name|database_name|database_user|password_env_var
```

Example:

```text
pathocore_api|pathocore-pathocore_db-1|pathocore_api|pathocore|PATHOCORE_DB_PASSWORD
```

## Manual Test

Run a dry-run first:

```bash
sudo bash scripts/backup-container-host.sh \
  --config /etc/ciber-container-backup.env \
  --dry-run
```

Then run a real backup without waiting for cron:

```bash
sudo bash scripts/backup-container-host.sh \
  --config /etc/ciber-container-backup.env
```

Check generated output:

```bash
sudo find /srv/containers/backup/host -maxdepth 3 -type f | sort
sudo tail -n 100 /var/log/local/container-backup/container-backup-$(date +%Y%m%d).log
```

## Daily Cron

Default schedule is daily at 02:15:

```bash
sudo REPO_PATH=/opt/container_apps/ciber-container-host-setup \
  bash scripts/install-backup-cron.sh --apply
```

Use a faster schedule only for testing:

```bash
sudo REPO_PATH=/opt/container_apps/ciber-container-host-setup \
  SCHEDULE="*/10 * * * *" \
  bash scripts/install-backup-cron.sh --apply
```

Return to the nightly schedule after testing:

```bash
sudo REPO_PATH=/opt/container_apps/ciber-container-host-setup \
  SCHEDULE="15 2 * * *" \
  bash scripts/install-backup-cron.sh --apply
```

Inspect the installed cron file:

```bash
sudo cat /etc/cron.d/ciber-container-backup
```

## Retention

Retention is controlled by:

```text
RETENTION_DAYS=14
```

The script removes old snapshot directories, database dump directories, and
backup logs older than this threshold.

Docker image archives are stored by immutable image ID and skipped once they
already exist. They are not aggressively removed by default because old image
IDs can be useful for rollback. Review image archive size periodically:

```bash
sudo du -hxd1 /srv/containers/backup/host/images | sort -h
```

## Restore Notes

Database dump restore example:

```bash
gzip -dc /srv/containers/backup/host/databases/<timestamp>/pathocore_api.sql.gz \
  | docker exec -i pathocore-pathocore_db-1 \
      mysql -upathocore -p pathocore_api
```

Use the correct database user/password for the target environment. Avoid putting
real passwords in shell history; prefer `MYSQL_PWD` or an interactive prompt.

Docker image restore example:

```bash
gzip -dc /srv/containers/backup/host/images/<image_id>.tar.gz | docker load
```

Bind mount and volume snapshots can be inspected under:

```text
/srv/containers/backup/host/snapshots/<timestamp>/
```

Restores should be done during a maintenance window and after stopping affected
containers.
