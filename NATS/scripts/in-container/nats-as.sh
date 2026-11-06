#!/bin/sh
# Entry point of the nats-box tools container (see docker-compose.yaml).
#
#   nats-as.sh <identity> [nats CLI arguments...]
#   nats-as.sh <identity> sh <script> [arguments...]
#
# <identity> is one of the users in config/accounts.conf. Its password is read
# from the Compose secret /run/secrets/nats_<identity>_password and exported
# only to the nats process (never on a command line or in `docker inspect`).
# NATS_URL and NATS_CA come from the service environment.
set -eu

identity="${1:-}"
case "$identity" in
  sys-admin | app-admin | orders-publisher | orders-consumer) ;;
  *)
    echo "usage: <sys-admin|app-admin|orders-publisher|orders-consumer> [nats args... | sh script args...]" >&2
    exit 64
    ;;
esac
shift

secret="/run/secrets/nats_$(printf '%s' "$identity" | tr '-' '_')_password"
[ -r "$secret" ] || {
  echo "nats-as: cannot read $secret (run scripts/setup.sh on the host)" >&2
  exit 1
}

NATS_USER="$identity"
NATS_PASSWORD="$(cat "$secret")"
export NATS_USER NATS_PASSWORD

# Least-privilege users may only subscribe to their own inbox prefix.
case "$identity" in
  orders-publisher) NATS_INBOX_PREFIX="_INBOX_orders_publisher" ;;
  orders-consumer) NATS_INBOX_PREFIX="_INBOX_orders_consumer" ;;
  *) NATS_INBOX_PREFIX="" ;;
esac
export NATS_INBOX_PREFIX

if [ "${1:-}" = "sh" ]; then
  shift
  exec /bin/sh "$@"
fi
if [ -n "$NATS_INBOX_PREFIX" ]; then
  exec nats --inbox-prefix "$NATS_INBOX_PREFIX" "$@"
fi
exec nats "$@"
