# Backups

This repository includes a local backup script for CIBER container VMs.

The script is intentionally simple: it writes backups to the same host under
`/srv/containers/backup/host`. If long-term retention is required, that folder
should be copied to external storage by the agreed institutional backup policy.

## What Is Backed Up

| Element | Content | Method / Format | Destination |
|---|---|---|---|
| Bind mounts | `/srv/containers/bind` | Incremental snapshot with `rsync --link-dest` | `/srv/containers/backup/host/snapshots/<timestamp>/bind/` |
| Docker volumes | Docker named volume mountpoints | Incremental snapshot with `rsync --link-dest` | `/srv/containers/backup/host/snapshots/<timestamp>/volumes/` |
| Docker images | Local Docker images | `docker save` compressed as `.tar.gz`, one file per image ID | `/srv/containers/backup/host/images/<image_id>.tar.gz` |
| MySQL/MariaDB databases | Configured databases | `mysqldump` compressed as `.sql.gz` | `/srv/containers/backup/host/databases/<timestamp>/<backup_name>.sql.gz` |
| Backup logs | Script execution output | Daily log file | `/var/log/local/container-backup/container-backup-YYYYMMDD.log` |

Database dumps are the primary recovery artifact for MySQL/MariaDB data. Volume
snapshots are useful for files, bind-mounted state, and inspection, but live
database volumes should not be the only database recovery source.

MySQL dumps use:

```text
--single-transaction --quick --routines --triggers --no-tablespaces
```

`--no-tablespaces` avoids requiring the global MySQL `PROCESS` privilege.

## Configuration

Create the local configuration file:

```bash
sudo cp templates/env/ciber-container-backup.example.env /etc/ciber-container-backup.env
sudo chmod 0600 /etc/ciber-container-backup.env
sudo vim /etc/ciber-container-backup.env
```

Do not commit `/etc/ciber-container-backup.env`; it may contain database
passwords.

Important settings:

| Setting | Purpose | Default |
|---|---|---|
| `BACKUP_ROOT` | Backup destination root | `/srv/containers/backup/host` |
| `LOG_DIR` | Backup log directory | `/var/log/local/container-backup` |
| `CONTAINER_BIND_ROOT` | Bind mount root to snapshot | `/srv/containers/bind` |
| `BACKUP_RETENTION_DAYS` | Retention for snapshots and database dumps | `14` |
| `LOG_RETENTION_DAYS` | Retention for backup execution logs | `90` |
| `BACKUP_BIND_MOUNTS` | Enable bind mount backups | `true` |
| `BACKUP_DOCKER_VOLUMES` | Enable Docker volume backups | `true` |
| `BACKUP_DOCKER_IMAGES` | Enable Docker image backups | `true` |
| `BACKUP_DATABASES` | Enable SQL dumps | `true` |

Legacy configs that still define `RETENTION_DAYS` continue to work. New configs
should use `BACKUP_RETENTION_DAYS` and `LOG_RETENTION_DAYS`.

## Required Values To Review

Before enabling backups on a VM, review these values in
`/etc/ciber-container-backup.env`:

| Setting | Why it matters |
|---|---|
| `BACKUP_ROOT` | Main destination for generated backups. Confirm this path has enough disk space. |
| `LOG_DIR` | Directory where backup execution logs are written. |
| `CONTAINER_BIND_ROOT` | Root folder for bind mounts that should be snapshotted. |
| `BACKUP_RETENTION_DAYS` | Number of days to keep snapshots and SQL dumps. |
| `LOG_RETENTION_DAYS` | Number of days to keep backup execution logs. |
| `PATHOCORE_DB_PASSWORD` | Password used to dump the PathoCore API database. |
| `KEYCLOAK_DB_PASSWORD` | Password used to dump the Keycloak database. |
| `MEPRAM_OMOP_DB_PASSWORD` | Password used to dump the MePRAM OMOP API database. |
| `CIBER_BACKUP_DATABASES` | List of databases to dump, including backup name, container, database, user, and password variable. |

Each database entry uses this format:

```text
backup_name|container_name|database_name|database_user|password_env_var
```

Example:

```text
pathocore_api|pathocore-pathocore_db-1|pathocore_api|pathocore|PATHOCORE_DB_PASSWORD
```

Typical PathoCore/MEPRAM example:

```text
CIBER_BACKUP_DATABASES="
pathocore_api|pathocore-pathocore_db-1|pathocore_api|pathocore|PATHOCORE_DB_PASSWORD
keycloak|pathocore-keycloak_db-1|keycloak|keycloak|KEYCLOAK_DB_PASSWORD
mepram_omop_api|pathocore-mepram_omop_db-1|mepram_omop_api|mepram|MEPRAM_OMOP_DB_PASSWORD
"
```

## Run Manually

Dry run:

```bash
sudo bash scripts/backup-container-host.sh \
  --config /etc/ciber-container-backup.env \
  --dry-run
```

Real backup:

```bash
sudo bash scripts/backup-container-host.sh \
  --config /etc/ciber-container-backup.env
```

Check output:

```bash
sudo find /srv/containers/backup/host -maxdepth 3 -type f | sort
sudo tail -n 100 /var/log/local/container-backup/container-backup-$(date +%Y%m%d).log
```

## Cron

Install the default nightly cron:

```bash
sudo REPO_PATH=/opt/container_apps/ciber-container-host-setup \
  bash scripts/install-backup-cron.sh --apply
```

| Mode | Schedule | Cron expression |
|---|---|---|
| Default | Daily at 02:15 | `15 2 * * *` |
| Temporary test | Every 10 minutes | `*/10 * * * *` |

Temporary test schedule:

```bash
sudo REPO_PATH=/opt/container_apps/ciber-container-host-setup \
  SCHEDULE="*/10 * * * *" \
  bash scripts/install-backup-cron.sh --apply
```

Return to the default schedule:

```bash
sudo REPO_PATH=/opt/container_apps/ciber-container-host-setup \
  SCHEDULE="15 2 * * *" \
  bash scripts/install-backup-cron.sh --apply
```

Inspect the installed cron:

```bash
sudo cat /etc/cron.d/ciber-container-backup
```

## Retention

| Artifact | Retention |
|---|---|
| Snapshots | `BACKUP_RETENTION_DAYS` |
| SQL dumps | `BACKUP_RETENTION_DAYS` |
| Logs | `LOG_RETENTION_DAYS` |
| Docker image archives | Not automatically pruned |

Docker image archives are saved by image ID and skipped if already present. They
can grow over time, so review disk usage periodically:

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

Docker image restore example:

```bash
gzip -dc /srv/containers/backup/host/images/<image_id>.tar.gz | docker load
```

Restores should be done during a maintenance window and after stopping affected
containers.
