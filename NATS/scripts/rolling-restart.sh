#!/usr/bin/env bash
# Rolling restart or upgrade, one server at a time, gated on cluster health.
#
#   scripts/rolling-restart.sh            all servers (followers first, meta leader last)
#   scripts/rolling-restart.sh nats-2     selected server(s) only
#
# Use it for: image upgrades (set NATS_IMAGE in .env first), changes that a
# reload cannot apply (listen addresses, store_dir, sync_interval, lame duck
# settings, compose-level changes such as limits or ports), or host maintenance.
# Reloadable changes (accounts, users, TLS files, most settings) only need:
#   docker compose kill -s SIGHUP nats-1 nats-2 nats-3
#
# Never `docker compose up -d` a changed nats service set in one go: Compose
# would recreate all three at once and the cluster would lose quorum.
#
# Per server: cluster must be fully healthy -> recreate the container (Compose
# sends SIGUSR2: lame duck mode hands off leadership and drains clients) ->
# wait for the container healthcheck -> wait until the cluster is fully healthy
# again (meta current, all replicas caught up) before touching the next one.
SCRIPT_NAME=rolling-restart
# shellcheck source=scripts/lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
require_cmd docker

TIMEOUT="${ROLLING_TIMEOUT:-600}"
targets="${*:-$NATS_NODES}"
for t in $targets; do
  case " $NATS_NODES " in *" $t "*) ;; *) die "unknown server: $t" ;; esac
done

compose config --quiet
cluster_healthy() { "$NATS_DIR/scripts/check-cluster.sh" --quiet >/dev/null 2>&1; }
container_healthy() { [ "$(docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null)" = healthy ]; }

leader=""
for n in $NATS_NODES; do
  leader="$(node_monitor "$n" /jsz 2>/dev/null | grep -o '"leader": *"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/' || true)"
  [ -n "$leader" ] && break
done
order=""
for t in $targets; do
  if [ "$t" != "$leader" ]; then order="$order $t"; fi
done
case " $targets " in *" $leader "*) order="$order $leader" ;; esac
log "meta leader: ${leader:-unknown}; order:$order"

for node in $order; do
  wait_until "$TIMEOUT" "cluster fully healthy before restarting $node" cluster_healthy ||
    die "cluster is not healthy; fix it (scripts/check-cluster.sh) before continuing"
  log "recreating $node with image $(service_image "$node")"
  compose up -d --no-deps --force-recreate "$node"
  wait_until "$TIMEOUT" "$node container healthy" container_healthy "$node" ||
    die "$node did not become healthy: docker compose logs $node"
  wait_until "$TIMEOUT" "cluster fully healthy after $node" cluster_healthy ||
    die "cluster did not recover after $node; stop here and investigate"
done
log "done: $("$NATS_DIR/scripts/check-cluster.sh" --quiet 2>/dev/null)"
