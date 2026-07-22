#!/usr/bin/env bash
set -Eeuo pipefail

APPLY=false
ASSUME_YES=false
SCHEDULE="${SCHEDULE:-15 2 * * *}"
CONFIG_PATH="${CONFIG_PATH:-/etc/ciber-container-backup.env}"
CRON_PATH="${CRON_PATH:-/etc/cron.d/ciber-container-backup}"
REPO_PATH="${REPO_PATH:-$(pwd)}"

usage() {
  cat <<'EOF'
Usage:
  install-backup-cron.sh --dry-run
  sudo install-backup-cron.sh --apply [--yes]

Environment variables:
  SCHEDULE      cron expression, default: "15 2 * * *"
  CONFIG_PATH   backup config path, default: /etc/ciber-container-backup.env
  CRON_PATH     cron file path, default: /etc/cron.d/ciber-container-backup
  REPO_PATH     path to this repository, default: current directory
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      APPLY=true
      ;;
    --dry-run)
      APPLY=false
      ;;
    --yes|-y)
      ASSUME_YES=true
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

if [ "$(id -u)" -ne 0 ] && [ "$APPLY" = true ]; then
  printf "ERROR: --apply must be run as root, usually through sudo.\n" >&2
  exit 1
fi

backup_script="$REPO_PATH/scripts/backup-container-host.sh"
log_dir="/var/log/local/container-backup"
cron_content="$(cat <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$SCHEDULE root /bin/bash $backup_script --config $CONFIG_PATH
EOF
)"

if [ "$APPLY" = true ] && [ "$ASSUME_YES" = false ]; then
  cat <<EOF
This will install a host-level backup cron job.

Schedule:      $SCHEDULE
Config path:   $CONFIG_PATH
Cron path:     $CRON_PATH
Backup script: $backup_script

EOF
  read -r -p "Continue? Type 'yes' to apply: " answer
  if [ "$answer" != "yes" ]; then
    printf "Aborted.\n"
    exit 1
  fi
fi

if [ "$APPLY" = true ]; then
  if [ ! -x "$backup_script" ]; then
    chmod +x "$backup_script"
  fi
  install -d -m 0755 "$log_dir"
  printf "%s\n" "$cron_content" > "$CRON_PATH"
  chmod 0644 "$CRON_PATH"
  printf "Installed backup cron: %s\n" "$CRON_PATH"
else
  printf "[dry-run] write %s:\n%s\n" "$CRON_PATH" "$cron_content"
fi
