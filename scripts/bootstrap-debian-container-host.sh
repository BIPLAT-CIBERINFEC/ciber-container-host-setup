#!/usr/bin/env bash
set -Eeuo pipefail

APPLY=false
ASSUME_YES=false

usage() {
  cat <<'EOF'
Usage:
  bootstrap-debian-container-host.sh --dry-run
  bootstrap-debian-container-host.sh --apply [--yes]

Environment variables:
  DEPLOY_USER              sudo-capable deployment user, default: current sudo user or current user
  APPS                     space-separated app names
  APP_ROOT                 default: /opt/container_apps
  LOG_ROOT                 default: /var/log/local
  CONTAINER_ROOT           default: /srv/containers
  DOCKER_DATA_ROOT         default: /srv/containers/storage
  CONTAINERD_ROOT          default: /srv/containers/containerd
  DOCKER_LOG_MAX_SIZE      default: 50m
  DOCKER_LOG_MAX_FILE      default: 5

Examples:
  bash scripts/bootstrap-debian-container-host.sh --dry-run
  sudo DEPLOY_USER=bioinfoadm bash scripts/bootstrap-debian-container-host.sh --apply
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

DEPLOY_USER="${DEPLOY_USER:-${SUDO_USER:-$(id -un)}}"
APPS="${APPS:-pathocore-web pathocore-api mepram-omop-api}"
APP_ROOT="${APP_ROOT:-/opt/container_apps}"
LOG_ROOT="${LOG_ROOT:-/var/log/local}"
CONTAINER_ROOT="${CONTAINER_ROOT:-/srv/containers}"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-$CONTAINER_ROOT/storage}"
CONTAINERD_ROOT="${CONTAINERD_ROOT:-$CONTAINER_ROOT/containerd}"
DOCKER_LOG_MAX_SIZE="${DOCKER_LOG_MAX_SIZE:-50m}"
DOCKER_LOG_MAX_FILE="${DOCKER_LOG_MAX_FILE:-5}"

timestamp() {
  date +%Y%m%d_%H%M%S
}

log() {
  printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"
}

run() {
  if [ "$APPLY" = true ]; then
    log "+ $*"
    "$@"
  else
    printf "[dry-run] %q" "$1"
    shift || true
    for arg in "$@"; do
      printf " %q" "$arg"
    done
    printf "\n"
  fi
}

write_file() {
  local path="$1"
  local content="$2"
  if [ "$APPLY" = true ]; then
    if [ -e "$path" ]; then
      local backup="${path}.backup.$(timestamp)"
      log "Backing up $path to $backup"
      cp -a "$path" "$backup"
    fi
    printf "%s\n" "$content" > "$path"
  else
    printf "[dry-run] write %s\n%s\n" "$path" "$content"
  fi
}

confirm_apply() {
  if [ "$APPLY" != true ] || [ "$ASSUME_YES" = true ]; then
    return
  fi

  cat <<EOF
This will install packages and modify host-level Docker/containerd config.

Deploy user:       $DEPLOY_USER
Applications:      $APPS
App root:          $APP_ROOT
Log root:          $LOG_ROOT
Container root:    $CONTAINER_ROOT
Docker data root:  $DOCKER_DATA_ROOT
containerd root:   $CONTAINERD_ROOT

EOF
  read -r -p "Continue? Type 'yes' to apply: " answer
  if [ "$answer" != "yes" ]; then
    printf "Aborted.\n"
    exit 1
  fi
}

ensure_debian() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    log "Detected OS: ${PRETTY_NAME:-unknown}"
    if [ "${ID:-}" != "debian" ] && [ "${ID_LIKE:-}" != "debian" ]; then
      printf "WARNING: this script is designed for Debian-like systems.\n" >&2
    fi
  fi
}

install_base_packages() {
  run apt-get update
  run apt-get install -y \
    ca-certificates curl gnupg lsb-release \
    git wget jq unzip rsync vim htop tree \
    net-tools \
    cron
}

install_docker() {
  run install -m 0755 -d /etc/apt/keyrings
  if [ "$APPLY" = true ]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  else
    printf "[dry-run] curl Docker Debian GPG key to /etc/apt/keyrings/docker.gpg\n"
  fi

  local distro codename
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu)
      distro="$ID"
      ;;
    *)
      printf "ERROR: Docker official repository setup is implemented only for Debian/Ubuntu. Detected ID=%s\n" "${ID:-unknown}" >&2
      exit 1
      ;;
  esac
  codename="${VERSION_CODENAME:-bookworm}"
  local source_line
  source_line="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${distro} ${codename} stable"
  write_file /etc/apt/sources.list.d/docker.list "$source_line"

  run apt-get update
  run apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

create_directories() {
  run install -d -m 0755 "$APP_ROOT"
  run install -d -m 0755 "$LOG_ROOT"
  run install -d -m 0755 "$CONTAINER_ROOT"
  run install -d -m 0755 "$CONTAINER_ROOT/backup"
  run install -d -m 0755 "$CONTAINER_ROOT/bind"
  run install -d -m 0755 "$CONTAINER_ROOT/shared"
  run install -d -m 0711 "$DOCKER_DATA_ROOT"
  run install -d -m 0711 "$CONTAINERD_ROOT"

  for app in $APPS; do
    run install -d -m 0755 "$APP_ROOT/$app"
    run install -d -m 0755 "$LOG_ROOT/$app/apps"
    run install -d -m 0755 "$LOG_ROOT/$app/apache"
    run install -d -m 0755 "$CONTAINER_ROOT/bind/$app"
    run install -d -m 0755 "$CONTAINER_ROOT/backup/$app"
    if id "$DEPLOY_USER" >/dev/null 2>&1; then
      run chown -R "$DEPLOY_USER:$DEPLOY_USER" \
        "$APP_ROOT/$app" \
        "$LOG_ROOT/$app" \
        "$CONTAINER_ROOT/bind/$app" \
        "$CONTAINER_ROOT/backup/$app"
    else
      printf "WARNING: deploy user does not exist yet: %s\n" "$DEPLOY_USER" >&2
    fi
  done
}

configure_docker() {
  local daemon_json
  daemon_json="$(cat <<EOF
{
  "data-root": "$DOCKER_DATA_ROOT",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "$DOCKER_LOG_MAX_SIZE",
    "max-file": "$DOCKER_LOG_MAX_FILE"
  }
}
EOF
)"
  run install -d -m 0755 /etc/docker
  write_file /etc/docker/daemon.json "$daemon_json"
}

configure_containerd() {
  run install -d -m 0755 /etc/containerd
  if [ "$APPLY" = true ]; then
    if command -v containerd >/dev/null 2>&1; then
      if [ -e /etc/containerd/config.toml ]; then
        cp -a /etc/containerd/config.toml "/etc/containerd/config.toml.backup.$(timestamp)"
      fi
      containerd config default > /etc/containerd/config.toml
      sed -i -E "s#^root = .*\$#root = \"$CONTAINERD_ROOT\"#" /etc/containerd/config.toml
    else
      printf "WARNING: containerd command not found; skipping config generation.\n" >&2
    fi
  else
    printf "[dry-run] generate /etc/containerd/config.toml and set root to %s\n" "$CONTAINERD_ROOT"
  fi
}

configure_user() {
  if id "$DEPLOY_USER" >/dev/null 2>&1; then
    run usermod -aG docker "$DEPLOY_USER"
  else
    printf "WARNING: deploy user does not exist: %s\n" "$DEPLOY_USER" >&2
  fi
}

restart_services() {
  run systemctl daemon-reload
  run systemctl enable containerd docker cron
  run systemctl restart containerd
  run systemctl restart docker
  run systemctl restart cron
}

validate() {
  log "Validation commands:"
  printf "  docker --version\n"
  printf "  docker compose version\n"
  printf "  docker info | grep -E 'Docker Root Dir|Storage Driver'\n"
}

main() {
  ensure_debian
  confirm_apply
  create_directories
  install_base_packages
  install_docker
  configure_docker
  configure_containerd
  configure_user
  restart_services
  validate

  if [ "$APPLY" = true ]; then
    log "Bootstrap complete. The deploy user may need to log out and back in for docker group membership."
  else
    log "Dry run complete. No changes were applied."
  fi
}

main "$@"
