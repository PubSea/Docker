#!/bin/bash
set -euo pipefail
: "${MYSQL_HOST:?MYSQL_HOST is required}"
: "${MYSQL_PORT:?MYSQL_PORT is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD is required}"
umask 077
password_file=$(mktemp)
trap 'rm -f "$password_file"' EXIT
printf '%s\n' "$MYSQL_PASSWORD" > "$password_file"
unset MYSQL_PASSWORD

# Bootstrap generates a dedicated metadata account and follows the current primary.
# Keep configuration on container restarts; --force refreshes it without duplicating
# the Router registration for this container.
ready=false
for attempt in {1..30}; do
    if mysqlrouter --bootstrap "${MYSQL_USER}@${MYSQL_HOST}:${MYSQL_PORT}" \
        --directory /tmp/mysqlrouter --force --user=mysqlrouter \
        --conf-bind-address=0.0.0.0 < "$password_file"; then
        ready=true
        break
    fi
    echo "Router bootstrap retry ${attempt}/30" >&2
    sleep 2
done
if [ "$ready" != true ]; then
    echo 'Router bootstrap failed' >&2
    exit 1
fi
rm -f "$password_file"
trap - EXIT
sed -i 's/^logging_folder=.*$/logging_folder=/' /tmp/mysqlrouter/mysqlrouter.conf
exec mysqlrouter --user=mysqlrouter --config /tmp/mysqlrouter/mysqlrouter.conf
