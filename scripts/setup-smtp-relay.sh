#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_PATH="/etc/ciber-smtp-relay.env"
MODE=""
APPLY=false
ASSUME_YES=false
PRINT_APP_ENV=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  setup-smtp-relay.sh --mode host-postfix --dry-run [--config <path>]
  setup-smtp-relay.sh --mode host-postfix --apply [--config <path>] [--yes]
  setup-smtp-relay.sh --mode container-postfix --dry-run [--config <path>]
  setup-smtp-relay.sh --mode container-postfix --apply [--config <path>] [--yes]
  setup-smtp-relay.sh --print-app-env [--config <path>]

Modes:
  host-postfix       Install/configure Postfix directly on the VM.
  container-postfix  Install a small Postfix relay container under /srv.

Configuration:
  Copy templates/env/ciber-smtp-relay.example.env to /etc/ciber-smtp-relay.env
  and edit the institutional SMTP values before running --apply.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      CONFIG_PATH="$2"
      shift
      ;;
    --mode)
      MODE="$2"
      shift
      ;;
    --apply)
      APPLY=true
      ;;
    --dry-run)
      APPLY=false
      ;;
    --yes|-y)
      ASSUME_YES=true
      ;;
    --print-app-env)
      PRINT_APP_ENV=true
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
fi

SMTP_RELAY_MODE="${MODE:-${SMTP_RELAY_MODE:-host-postfix}}"
SMTP_RELAY_UPSTREAM_HOST="${SMTP_RELAY_UPSTREAM_HOST:-${SMTP_RELAY_HOST:-}}"
SMTP_RELAY_UPSTREAM_PORT="${SMTP_RELAY_UPSTREAM_PORT:-25}"
SMTP_RELAY_TLS_SECURITY_LEVEL="${SMTP_RELAY_TLS_SECURITY_LEVEL:-may}"
SMTP_RELAY_TLS_CA_FILE="${SMTP_RELAY_TLS_CA_FILE:-/etc/ssl/certs/ca-certificates.crt}"
SMTP_RELAY_UPSTREAM_AUTH="${SMTP_RELAY_UPSTREAM_AUTH:-auto}"
SMTP_RELAY_UPSTREAM_USER="${SMTP_RELAY_UPSTREAM_USER:-}"
SMTP_RELAY_UPSTREAM_PASSWORD="${SMTP_RELAY_UPSTREAM_PASSWORD:-}"
SMTP_RELAY_MYHOSTNAME="${SMTP_RELAY_MYHOSTNAME:-ciber-smtp-relay}"
SMTP_RELAY_MYORIGIN="${SMTP_RELAY_MYORIGIN:-localhost}"
SMTP_RELAY_MYDESTINATION="${SMTP_RELAY_MYDESTINATION:-localhost}"
SMTP_RELAY_MYNETWORKS="${SMTP_RELAY_MYNETWORKS:-auto}"
SMTP_RELAY_INET_INTERFACES="${SMTP_RELAY_INET_INTERFACES:-auto}"
SMTP_RELAY_INET_PROTOCOLS="${SMTP_RELAY_INET_PROTOCOLS:-all}"
SMTP_RELAY_CONTAINER_ROOT="${SMTP_RELAY_CONTAINER_ROOT:-/srv/containers/shared/smtp-relay}"
SMTP_RELAY_CONTAINER_NAME="${SMTP_RELAY_CONTAINER_NAME:-ciber-smtp-relay}"
SMTP_RELAY_BIND_HOST="${SMTP_RELAY_BIND_HOST:-0.0.0.0}"
SMTP_RELAY_BIND_PORT="${SMTP_RELAY_BIND_PORT:-25}"
SMTP_APP_HOST="${SMTP_APP_HOST:-host.docker.internal}"
SMTP_APP_PORT="${SMTP_APP_PORT:-$SMTP_RELAY_BIND_PORT}"
SMTP_DEFAULT_FROM_EMAIL="${SMTP_DEFAULT_FROM_EMAIL:-change_me@example.org}"

AUTH_ENABLED=false
case "$SMTP_RELAY_UPSTREAM_AUTH" in
  true|yes|1)
    AUTH_ENABLED=true
    ;;
  false|no|0)
    AUTH_ENABLED=false
    ;;
  auto)
    if [ -n "$SMTP_RELAY_UPSTREAM_USER" ] || [ -n "$SMTP_RELAY_UPSTREAM_PASSWORD" ]; then
      AUTH_ENABLED=true
    fi
    ;;
  *)
    printf "ERROR: invalid SMTP_RELAY_UPSTREAM_AUTH: %s\n" "$SMTP_RELAY_UPSTREAM_AUTH" >&2
    exit 2
    ;;
esac

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

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf "ERROR: required command not found: %s\n" "$1" >&2
    exit 1
  }
}

validate_common_config() {
  case "$SMTP_RELAY_MODE" in
    host-postfix|container-postfix)
      ;;
    *)
      printf "ERROR: invalid mode: %s\n" "$SMTP_RELAY_MODE" >&2
      usage >&2
      exit 2
      ;;
  esac

  if [ -z "$SMTP_RELAY_UPSTREAM_HOST" ]; then
    printf "ERROR: SMTP_RELAY_UPSTREAM_HOST is required.\n" >&2
    exit 1
  fi

  if [ "$AUTH_ENABLED" = true ]; then
    if [ -z "$SMTP_RELAY_UPSTREAM_USER" ] || [ -z "$SMTP_RELAY_UPSTREAM_PASSWORD" ]; then
      printf "ERROR: SMTP relay auth requires SMTP_RELAY_UPSTREAM_USER and SMTP_RELAY_UPSTREAM_PASSWORD.\n" >&2
      exit 1
    fi
  fi
}

require_root_for_apply() {
  if [ "$APPLY" = true ] && [ "$(id -u)" -ne 0 ]; then
    printf "ERROR: --apply must be run as root, usually through sudo.\n" >&2
    exit 1
  fi
}

confirm_apply() {
  if [ "$APPLY" != true ] || [ "$ASSUME_YES" = true ]; then
    return
  fi

  cat <<EOF
This will configure a host-level SMTP relay.

Mode:              $SMTP_RELAY_MODE
Upstream relay:    [$SMTP_RELAY_UPSTREAM_HOST]:$SMTP_RELAY_UPSTREAM_PORT
Upstream TLS:      $SMTP_RELAY_TLS_SECURITY_LEVEL
Upstream auth:     $AUTH_ENABLED
App SMTP host:     $SMTP_APP_HOST
App SMTP port:     $SMTP_APP_PORT

EOF
  read -r -p "Continue? Type 'yes' to apply: " answer
  if [ "$answer" != "yes" ]; then
    printf "Aborted.\n"
    exit 1
  fi
}

join_by() {
  local separator="$1"
  shift
  local first=true
  local item

  for item in "$@"; do
    [ -n "$item" ] || continue
    if [ "$first" = true ]; then
      printf "%s" "$item"
      first=false
    else
      printf "%s%s" "$separator" "$item"
    fi
  done
}

docker_network_gateways() {
  command -v docker >/dev/null 2>&1 || return 0
  docker network ls -q 2>/dev/null | while IFS= read -r network_id; do
    [ -n "$network_id" ] || continue
    docker network inspect "$network_id" \
      --format '{{range .IPAM.Config}}{{if .Gateway}}{{println .Gateway}}{{end}}{{end}}' \
      2>/dev/null || true
  done | sort -u
}

docker_network_subnets() {
  command -v docker >/dev/null 2>&1 || return 0
  docker network ls -q 2>/dev/null | while IFS= read -r network_id; do
    [ -n "$network_id" ] || continue
    docker network inspect "$network_id" \
      --format '{{range .IPAM.Config}}{{if .Subnet}}{{println .Subnet}}{{end}}{{end}}' \
      2>/dev/null || true
  done | sort -u
}

effective_inet_interfaces() {
  if [ "$SMTP_RELAY_INET_INTERFACES" != "auto" ]; then
    printf "%s" "$SMTP_RELAY_INET_INTERFACES"
    return
  fi

  local values=("127.0.0.1")
  if [ "$SMTP_RELAY_INET_PROTOCOLS" != "ipv4" ]; then
    values+=("::1")
  fi

  local gateway
  while IFS= read -r gateway; do
    [ -n "$gateway" ] || continue
    values+=("$gateway")
  done < <(docker_network_gateways)

  join_by ", " "${values[@]}"
}

effective_mynetworks() {
  if [ "$SMTP_RELAY_MYNETWORKS" != "auto" ]; then
    printf "%s" "$SMTP_RELAY_MYNETWORKS"
    return
  fi

  local values=("127.0.0.0/8")
  if [ "$SMTP_RELAY_INET_PROTOCOLS" != "ipv4" ]; then
    values+=("[::1]/128")
  fi

  local subnet
  while IFS= read -r subnet; do
    [ -n "$subnet" ] || continue
    values+=("$subnet")
  done < <(docker_network_subnets)

  join_by " " "${values[@]}"
}

postconf_set() {
  local key="$1"
  local value="$2"
  run postconf -e "$key = $value"
}

configure_host_sasl() {
  local relay_key="[$SMTP_RELAY_UPSTREAM_HOST]:$SMTP_RELAY_UPSTREAM_PORT"

  if [ "$AUTH_ENABLED" = true ]; then
    if [ "$APPLY" = true ]; then
      umask 077
      printf "%s %s:%s\n" "$relay_key" "$SMTP_RELAY_UPSTREAM_USER" "$SMTP_RELAY_UPSTREAM_PASSWORD" \
        > /etc/postfix/sasl_passwd
      postmap /etc/postfix/sasl_passwd
      chmod 0600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
    else
      printf "[dry-run] write /etc/postfix/sasl_passwd with credentials for %s\n" "$relay_key"
      printf "[dry-run] postmap /etc/postfix/sasl_passwd\n"
    fi
    postconf_set smtp_sasl_auth_enable yes
    postconf_set smtp_sasl_password_maps hash:/etc/postfix/sasl_passwd
    postconf_set smtp_sasl_security_options noanonymous
    postconf_set smtp_sasl_tls_security_options noanonymous
  else
    postconf_set smtp_sasl_auth_enable no
  fi
}

setup_host_postfix() {
  require_root_for_apply
  require_command apt-get

  local inet_interfaces mynetworks
  inet_interfaces="$(effective_inet_interfaces)"
  mynetworks="$(effective_mynetworks)"

  if [ "$APPLY" = true ]; then
    export DEBIAN_FRONTEND=noninteractive
    printf "postfix postfix/mailname string %s\n" "$SMTP_RELAY_MYHOSTNAME" | debconf-set-selections
    printf "postfix postfix/main_mailer_type select Satellite system\n" | debconf-set-selections
  else
    printf "[dry-run] preseed Postfix debconf values\n"
  fi

  run apt-get update
  run apt-get install -y postfix ca-certificates libsasl2-modules

  postconf_set relayhost "[$SMTP_RELAY_UPSTREAM_HOST]:$SMTP_RELAY_UPSTREAM_PORT"
  postconf_set smtp_tls_security_level "$SMTP_RELAY_TLS_SECURITY_LEVEL"
  postconf_set smtp_tls_CAfile "$SMTP_RELAY_TLS_CA_FILE"
  postconf_set smtp_tls_CApath /etc/ssl/certs
  postconf_set smtp_tls_loglevel 1
  postconf_set myhostname "$SMTP_RELAY_MYHOSTNAME"
  postconf_set myorigin "$SMTP_RELAY_MYORIGIN"
  postconf_set mydestination "$SMTP_RELAY_MYDESTINATION"
  postconf_set inet_interfaces "$inet_interfaces"
  postconf_set inet_protocols "$SMTP_RELAY_INET_PROTOCOLS"
  postconf_set mynetworks "$mynetworks"
  postconf_set smtpd_relay_restrictions "permit_mynetworks reject_unauth_destination"
  postconf_set smtpd_recipient_restrictions "permit_mynetworks reject_unauth_destination"
  configure_host_sasl

  run systemctl enable postfix
  run systemctl restart postfix
}

write_container_env() {
  local env_path="$SMTP_RELAY_CONTAINER_ROOT/smtp-relay.env"
  local container_inet_interfaces="$SMTP_RELAY_INET_INTERFACES"
  local container_mynetworks="$SMTP_RELAY_MYNETWORKS"
  local content

  if [ "$container_inet_interfaces" = "auto" ]; then
    container_inet_interfaces="all"
  fi
  if [ "$container_mynetworks" = "auto" ]; then
    container_mynetworks="127.0.0.0/8 172.16.0.0/12 [::1]/128"
  fi

  content="$(cat <<EOF
SMTP_RELAY_UPSTREAM_HOST="$SMTP_RELAY_UPSTREAM_HOST"
SMTP_RELAY_UPSTREAM_PORT="$SMTP_RELAY_UPSTREAM_PORT"
SMTP_RELAY_TLS_SECURITY_LEVEL="$SMTP_RELAY_TLS_SECURITY_LEVEL"
SMTP_RELAY_TLS_CA_FILE="$SMTP_RELAY_TLS_CA_FILE"
SMTP_RELAY_UPSTREAM_AUTH="$SMTP_RELAY_UPSTREAM_AUTH"
SMTP_RELAY_UPSTREAM_USER="$SMTP_RELAY_UPSTREAM_USER"
SMTP_RELAY_UPSTREAM_PASSWORD="$SMTP_RELAY_UPSTREAM_PASSWORD"
SMTP_RELAY_MYHOSTNAME="$SMTP_RELAY_MYHOSTNAME"
SMTP_RELAY_MYORIGIN="$SMTP_RELAY_MYORIGIN"
SMTP_RELAY_MYDESTINATION="$SMTP_RELAY_MYDESTINATION"
SMTP_RELAY_MYNETWORKS="$container_mynetworks"
SMTP_RELAY_INET_INTERFACES="$container_inet_interfaces"
SMTP_RELAY_INET_PROTOCOLS="$SMTP_RELAY_INET_PROTOCOLS"
SMTP_RELAY_CONTAINER_NAME="$SMTP_RELAY_CONTAINER_NAME"
SMTP_RELAY_BIND_HOST="$SMTP_RELAY_BIND_HOST"
SMTP_RELAY_BIND_PORT="$SMTP_RELAY_BIND_PORT"
EOF
)"

  if [ "$APPLY" = true ]; then
    write_file "$env_path" "$content"
    run chmod 0600 "$env_path"
  else
    printf "[dry-run] write %s with SMTP relay settings; password redacted\n" "$env_path"
  fi
}

setup_container_postfix() {
  require_root_for_apply
  require_command docker

  run install -d -m 0755 "$SMTP_RELAY_CONTAINER_ROOT"
  run cp "$REPO_ROOT/docker/smtp-relay/Dockerfile" "$SMTP_RELAY_CONTAINER_ROOT/Dockerfile"
  run cp "$REPO_ROOT/docker/smtp-relay/entrypoint.sh" "$SMTP_RELAY_CONTAINER_ROOT/entrypoint.sh"
  run cp "$REPO_ROOT/docker/smtp-relay/main.cf.template" "$SMTP_RELAY_CONTAINER_ROOT/main.cf.template"
  run cp "$REPO_ROOT/templates/smtp-relay-container/docker-compose.yml" "$SMTP_RELAY_CONTAINER_ROOT/docker-compose.yml"
  write_container_env

  run docker compose \
    --env-file "$SMTP_RELAY_CONTAINER_ROOT/smtp-relay.env" \
    -f "$SMTP_RELAY_CONTAINER_ROOT/docker-compose.yml" \
    up -d --build
}

print_app_env() {
  cat <<EOF
EMAIL_HOST=$SMTP_APP_HOST
EMAIL_PORT=$SMTP_APP_PORT
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
EMAIL_USE_TLS=false
DEFAULT_FROM_EMAIL=$SMTP_DEFAULT_FROM_EMAIL
EOF
}

main() {
  if [ "$PRINT_APP_ENV" = true ]; then
    print_app_env
    exit 0
  fi

  validate_common_config
  confirm_apply

  case "$SMTP_RELAY_MODE" in
    host-postfix)
      setup_host_postfix
      ;;
    container-postfix)
      setup_container_postfix
      ;;
  esac

  log "SMTP relay setup finished."
  log "Application containers should use:"
  print_app_env
}

main "$@"
