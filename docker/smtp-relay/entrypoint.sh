#!/usr/bin/env bash
set -euo pipefail

: "${SMTP_RELAY_HOST:?SMTP_RELAY_HOST is required}"

export SMTP_RELAY_PORT="${SMTP_RELAY_PORT:-25}"
export SMTP_RELAY_TLS_SECURITY_LEVEL="${SMTP_RELAY_TLS_SECURITY_LEVEL:-may}"
export SMTP_RELAY_TLS_CA_FILE="${SMTP_RELAY_TLS_CA_FILE:-/etc/ssl/certs/ca-certificates.crt}"
export SMTP_RELAY_UPSTREAM_AUTH="${SMTP_RELAY_UPSTREAM_AUTH:-auto}"
export SMTP_RELAY_UPSTREAM_USER="${SMTP_RELAY_UPSTREAM_USER:-}"
export SMTP_RELAY_UPSTREAM_PASSWORD="${SMTP_RELAY_UPSTREAM_PASSWORD:-}"
export SMTP_RELAY_MYHOSTNAME="${SMTP_RELAY_MYHOSTNAME:-ciber-smtp-relay}"
export SMTP_RELAY_MYORIGIN="${SMTP_RELAY_MYORIGIN:-localhost}"
export SMTP_RELAY_MYDESTINATION="${SMTP_RELAY_MYDESTINATION:-localhost}"
export SMTP_RELAY_MYNETWORKS="${SMTP_RELAY_MYNETWORKS:-127.0.0.0/8 172.16.0.0/12 [::1]/128}"
export SMTP_RELAY_INET_INTERFACES="${SMTP_RELAY_INET_INTERFACES:-all}"
export SMTP_RELAY_INET_PROTOCOLS="${SMTP_RELAY_INET_PROTOCOLS:-all}"

auth_enabled=false
case "$SMTP_RELAY_UPSTREAM_AUTH" in
  true|yes|1)
    auth_enabled=true
    ;;
  false|no|0)
    auth_enabled=false
    ;;
  auto)
    if [ -n "$SMTP_RELAY_UPSTREAM_USER" ] || [ -n "$SMTP_RELAY_UPSTREAM_PASSWORD" ]; then
      auth_enabled=true
    fi
    ;;
  *)
    printf "ERROR: invalid SMTP_RELAY_UPSTREAM_AUTH: %s\n" "$SMTP_RELAY_UPSTREAM_AUTH" >&2
    exit 2
    ;;
esac

if [ "$auth_enabled" = true ]; then
  if [ -z "$SMTP_RELAY_UPSTREAM_USER" ] || [ -z "$SMTP_RELAY_UPSTREAM_PASSWORD" ]; then
    printf "ERROR: SMTP relay auth requires SMTP_RELAY_UPSTREAM_USER and SMTP_RELAY_UPSTREAM_PASSWORD.\n" >&2
    exit 1
  fi
  export SMTP_RELAY_SASL_AUTH_ENABLE=yes
  umask 077
  printf "[%s]:%s %s:%s\n" \
    "$SMTP_RELAY_HOST" \
    "$SMTP_RELAY_PORT" \
    "$SMTP_RELAY_UPSTREAM_USER" \
    "$SMTP_RELAY_UPSTREAM_PASSWORD" > /etc/postfix/sasl_passwd
  postmap /etc/postfix/sasl_passwd
  chmod 0600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
else
  export SMTP_RELAY_SASL_AUTH_ENABLE=no
  rm -f /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
fi

envsubst '$SMTP_RELAY_HOST $SMTP_RELAY_PORT $SMTP_RELAY_TLS_SECURITY_LEVEL $SMTP_RELAY_TLS_CA_FILE $SMTP_RELAY_SASL_AUTH_ENABLE $SMTP_RELAY_MYHOSTNAME $SMTP_RELAY_MYORIGIN $SMTP_RELAY_MYDESTINATION $SMTP_RELAY_MYNETWORKS $SMTP_RELAY_INET_INTERFACES $SMTP_RELAY_INET_PROTOCOLS' \
    < /etc/postfix/main.cf.template > /etc/postfix/main.cf

# Debian runs the smtp delivery process chrooted. Keep resolver files available
# inside the chroot so external relay hosts can be resolved reliably.
mkdir -p /var/spool/postfix/etc
cp /etc/resolv.conf /var/spool/postfix/etc/resolv.conf
cp /etc/hosts /var/spool/postfix/etc/hosts
cp /etc/services /var/spool/postfix/etc/services

postfix check

exec "$@"
