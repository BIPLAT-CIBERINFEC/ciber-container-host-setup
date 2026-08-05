#!/usr/bin/env bash
set -Eeuo pipefail

section() {
  printf "\n== %s ==\n" "$1"
}

run_optional() {
  local description="$1"
  shift
  printf "\n# %s\n" "$description"
  if command -v "$1" >/dev/null 2>&1; then
    "$@" || true
  else
    printf "missing command: %s\n" "$1"
  fi
}

section "Host"
run_optional "hostnamectl" hostnamectl
run_optional "kernel" uname -a

section "Resources"
run_optional "disk usage" df -h
run_optional "memory" free -h
run_optional "cpu" lscpu

section "Network"
run_optional "addresses" ip a
run_optional "routes" ip route

section "DNS and Internet"
run_optional "resolve github.com" getent hosts github.com
if command -v curl >/dev/null 2>&1; then
  printf "\n# https://github.com\n"
  curl -I --max-time 10 https://github.com || true
  printf "\n# Docker registry\n"
  curl -I --max-time 10 https://registry-1.docker.io || true
else
  printf "missing command: curl\n"
fi

section "Docker"
if command -v docker >/dev/null 2>&1; then
  docker --version || true
  docker compose version || true
  docker info 2>/dev/null | grep -E "Docker Root Dir|Storage Driver|Cgroup Driver|Logging Driver" || true
  docker ps --format "table {{.Names}}\t{{.Status}}" || true
else
  printf "docker is not installed or not in PATH\n"
fi

section "Expected CIBER Directories"
for path in \
  /opt/container_apps \
  /srv/containers \
  /srv/containers/backup \
  /srv/containers/bind \
  /srv/containers/shared \
  /srv/containers/storage \
  /srv/containers/containerd \
  /var/log/local
do
  if [ -e "$path" ]; then
    ls -ld "$path"
  else
    printf "missing: %s\n" "$path"
  fi
done

section "Large /var and /srv Consumers"
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo du -hxd1 /var 2>/dev/null | sort -h || true
  sudo du -hxd1 /srv 2>/dev/null | sort -h || true
else
  du -hxd1 /var 2>/dev/null | sort -h || true
  du -hxd1 /srv 2>/dev/null | sort -h || true
fi

section "Done"
printf "Host audit completed. No changes were applied.\n"
