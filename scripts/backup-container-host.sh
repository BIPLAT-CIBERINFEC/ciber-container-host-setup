#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_PATH="/etc/ciber-container-backup.env"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  backup-container-host.sh [--config <path>] [--dry-run]

Creates host-level backups for CIBER container machines:
  - bind mounts under /srv/containers/bind
  - Docker named volumes using their mountpoints
  - Docker images, saved once per image ID
  - configured MySQL/MariaDB databases through logical dumps

The script is designed for cron execution and writes logs under LOG_DIR.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      CONFIG_PATH="$2"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf "Unknown argument: %s\n" "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -f "$CONFIG_PATH" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_PATH"
elif [ "$DRY_RUN" = false ]; then
  printf "ERROR: backup config not found: %s\n" "$CONFIG_PATH" >&2
  exit 1
fi

BACKUP_ROOT="${BACKUP_ROOT:-/srv/containers/backup/host}"
LOG_DIR="${LOG_DIR:-/var/log/local/container-backup}"
CONTAINER_BIND_ROOT="${CONTAINER_BIND_ROOT:-/srv/containers/bind}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
BACKUP_BIND_MOUNTS="${BACKUP_BIND_MOUNTS:-true}"
BACKUP_DOCKER_VOLUMES="${BACKUP_DOCKER_VOLUMES:-true}"
BACKUP_DOCKER_IMAGES="${BACKUP_DOCKER_IMAGES:-true}"
BACKUP_DATABASES="${BACKUP_DATABASES:-true}"
DOCKER_VOLUME_EXCLUDE_REGEX="${DOCKER_VOLUME_EXCLUDE_REGEX:-}"
CIBER_BACKUP_DATABASES="${CIBER_BACKUP_DATABASES:-}"

timestamp="$(date +%Y%m%d_%H%M%S)"
log_file="$LOG_DIR/container-backup-$(date +%Y%m%d).log"

run() {
  if [ "$DRY_RUN" = true ]; then
    printf "[dry-run] %q" "$1"
    shift || true
    for arg in "$@"; do
      printf " %q" "$arg"
    done
    printf "\n"
  else
    "$@"
  fi
}

log() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf "ERROR: required command not found: %s\n" "$1" >&2
    exit 1
  }
}

prepare_paths() {
  if [ "$DRY_RUN" = false ]; then
    mkdir -p "$LOG_DIR" "$BACKUP_ROOT/snapshots" "$BACKUP_ROOT/databases" "$BACKUP_ROOT/images"
    exec > >(tee -a "$log_file") 2>&1
  else
    printf "[dry-run] log file would be: %s\n" "$log_file"
  fi
}

rsync_incremental() {
  local source_path="$1"
  local destination_path="$2"
  local link_dest="$3"
  local rsync_args=(-aH --delete --numeric-ids)

  if [ -d "$link_dest" ]; then
    rsync_args+=(--link-dest="$link_dest")
  fi

  run mkdir -p "$destination_path"
  run rsync "${rsync_args[@]}" "$source_path/" "$destination_path/"
}

backup_bind_mounts() {
  [ "$BACKUP_BIND_MOUNTS" = true ] || return 0
  log "Backing up bind mounts from $CONTAINER_BIND_ROOT"

  local snapshot_dir="$BACKUP_ROOT/snapshots/$timestamp/bind"
  local latest_dir="$BACKUP_ROOT/snapshots/latest/bind"

  if [ ! -d "$CONTAINER_BIND_ROOT" ]; then
    log "Bind mount root does not exist, skipping: $CONTAINER_BIND_ROOT"
    return 0
  fi

  rsync_incremental "$CONTAINER_BIND_ROOT" "$snapshot_dir" "$latest_dir"
}

backup_docker_volumes() {
  [ "$BACKUP_DOCKER_VOLUMES" = true ] || return 0
  log "Backing up Docker named volumes"

  local volume_name mountpoint snapshot_dir latest_dir

  while IFS= read -r volume_name; do
    [ -n "$volume_name" ] || continue
    if [ -n "$DOCKER_VOLUME_EXCLUDE_REGEX" ] \
      && printf "%s\n" "$volume_name" | grep -Eq "$DOCKER_VOLUME_EXCLUDE_REGEX"; then
      log "Skipping excluded volume: $volume_name"
      continue
    fi

    mountpoint="$(docker volume inspect -f '{{.Mountpoint}}' "$volume_name")"
    if [ ! -d "$mountpoint" ]; then
      log "Volume mountpoint not found, skipping $volume_name: $mountpoint"
      continue
    fi

    snapshot_dir="$BACKUP_ROOT/snapshots/$timestamp/volumes/$volume_name"
    latest_dir="$BACKUP_ROOT/snapshots/latest/volumes/$volume_name"
    rsync_incremental "$mountpoint" "$snapshot_dir" "$latest_dir"
  done < <(docker volume ls -q)
}

backup_docker_images() {
  [ "$BACKUP_DOCKER_IMAGES" = true ] || return 0
  log "Backing up Docker images by immutable image ID"

  local image_dir="$BACKUP_ROOT/images"
  local manifest="$BACKUP_ROOT/images/image-manifest-$timestamp.tsv"
  local image_ref image_id image_file

  run mkdir -p "$image_dir"

  if [ "$DRY_RUN" = true ]; then
    docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' \
      | grep -v '^<none>:' || true
    return 0
  fi

  docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' \
    | grep -v '^<none>:' > "$manifest" || true

  awk '{print $2}' "$manifest" | sort -u | while IFS= read -r image_id; do
    [ -n "$image_id" ] || continue
    image_file="$image_dir/${image_id}.tar.gz"
    if [ -f "$image_file" ]; then
      log "Image already backed up, skipping: $image_id"
      continue
    fi
    log "Saving Docker image: $image_id"
    docker save "$image_id" | gzip -c > "$image_file"
  done

  while IFS= read -r image_ref image_id; do
    [ -n "${image_ref:-}" ] || continue
    printf "%s\t%s\n" "$image_ref" "$image_id"
  done < "$manifest" > "$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
}

backup_databases() {
  [ "$BACKUP_DATABASES" = true ] || return 0
  log "Backing up configured MySQL/MariaDB databases"

  if [ -z "$CIBER_BACKUP_DATABASES" ]; then
    log "No CIBER_BACKUP_DATABASES entries configured; skipping database dumps"
    return 0
  fi

  local db_dir="$BACKUP_ROOT/databases/$timestamp"
  local name container database user password_env password output
  run mkdir -p "$db_dir"

  while IFS='|' read -r name container database user password_env; do
    case "${name:-}" in
      ""|\#*) continue ;;
    esac
    password="${!password_env:-}"
    if [ -z "$password" ]; then
      printf "ERROR: password env var is empty or undefined for database '%s': %s\n" "$name" "$password_env" >&2
      exit 1
    fi

    output="$db_dir/${name}.sql.gz"
    log "Dumping database '$database' from container '$container' as '$name'"
    if [ "$DRY_RUN" = true ]; then
      printf "[dry-run] docker exec -e MYSQL_PWD=*** %s mysqldump --single-transaction --quick --routines --triggers --no-tablespaces -u%s %s | gzip > %s\n" \
        "$container" "$user" "$database" "$output"
    else
      docker exec -e MYSQL_PWD="$password" "$container" \
        mysqldump --single-transaction --quick --routines --triggers --no-tablespaces \
        -u"$user" "$database" | gzip -c > "$output"
    fi
  done <<< "$CIBER_BACKUP_DATABASES"
}

rotate_latest_snapshot() {
  local snapshot_root="$BACKUP_ROOT/snapshots"
  [ -d "$snapshot_root/$timestamp" ] || return 0

  if [ "$DRY_RUN" = true ]; then
    printf "[dry-run] update %s/latest -> %s\n" "$snapshot_root" "$timestamp"
  else
    rm -f "$snapshot_root/latest"
    ln -s "$timestamp" "$snapshot_root/latest"
  fi
}

apply_retention() {
  log "Applying retention policy: $RETENTION_DAYS days"
  run find "$BACKUP_ROOT/snapshots" -mindepth 1 -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" -exec rm -rf {} +
  run find "$BACKUP_ROOT/databases" -mindepth 1 -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" -exec rm -rf {} +
  run find "$LOG_DIR" -type f -name 'container-backup-*.log' -mtime +"$RETENTION_DAYS" -delete
}

main() {
  require_command docker
  require_command rsync
  require_command gzip
  require_command awk
  prepare_paths

  log "Starting CIBER container host backup"
  log "Backup root: $BACKUP_ROOT"
  log "Dry run: $DRY_RUN"

  backup_bind_mounts
  backup_docker_volumes
  backup_docker_images
  backup_databases
  rotate_latest_snapshot
  apply_retention

  log "Backup completed successfully"
}

main "$@"
