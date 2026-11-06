#!/usr/bin/env bash
# Restore drill: proves that a backup really restores, WITHOUT touching the
# cluster or its data.
#
#   scripts/restore-drill.sh                       newest backup in ./backups
#   scripts/restore-drill.sh backups/20261106T020000Z
#
# 1. starts a throwaway single-node NATS server (same pinned image) on a new
#    internal Docker network: no published ports, no route to the cluster
# 2. validates and restores every stream of the backup there (as R1)
# 3. compares messages / first and last sequence with the backup, checks the
#    consumers came back with their positions, reads first and last message
# 4. removes the server, its volume and the network (also on failure)
# Exit code 0 = PASS. Run it after every backup change and on a schedule.
SCRIPT_NAME=restore-drill
# shellcheck source=scripts/lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
require_cmd docker

backup="${1:-}"
if [ -z "$backup" ]; then
  # shellcheck disable=SC2012 # timestamp-named directories only
  backup="$(ls -1d "$NATS_DIR"/backups/[0-9]*T[0-9]*Z 2>/dev/null | sort | tail -n 1 || true)"
fi
[ -n "$backup" ] && [ -d "$backup" ] || die "no backup found (run scripts/backup.sh first)"
backup="$(cd "$backup" && pwd)"
case "$backup" in
  "$NATS_DIR/backups/"*) rel="${backup#"$NATS_DIR"/backups/}" ;;
  *) die "the backup must be a directory under $NATS_DIR/backups" ;;
esac

id="$(date +%s)-$$"
net="nats-restore-drill-$id"
srv="nats-restore-drill-$id"
nats_image="$(service_image nats-1)"
box_image="$(service_image nats-box)"

cleanup() {
  docker rm -f -v "$srv" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "drill for backups/$rel on throwaway server $srv"
docker network create --internal "$net" >/dev/null
docker run -d --name "$srv" --network "$net" --network-alias restore-drill \
  --read-only --cap-drop ALL --security-opt no-new-privileges:true -v /data \
  "$nats_image" -js -sd /data -n restore-drill -m 8222 >/dev/null
wait_until 60 "throwaway server ready" \
  docker exec "$srv" wget -q -T 2 -O /dev/null http://127.0.0.1:8222/healthz

# Same identity as the tools container (NATS_UID/NATS_GID from .env).
docker run --rm --network "$net" --user "$(env_get NATS_UID):$(env_get NATS_GID)" \
  --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges:true \
  -e NATS_URL=nats://restore-drill:4222 -e HOME=/tmp -e XDG_CONFIG_HOME=/tmp/.config -w /tmp \
  -v "$NATS_DIR/backups:/backups:ro" -v "$NATS_DIR/scripts/in-container:/opt/nats-tools:ro" \
  --entrypoint /bin/sh "$box_image" /opt/nats-tools/restore-drill.sh "/backups/$rel"
