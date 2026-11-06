#!/usr/bin/env bash
# End-to-end validation on a temporary R3 stream (VALIDATE_<run id>), which is
# deleted afterwards. Application streams are never read or written.
#
#   scripts/validate.sh                 non-disruptive: membership, quorum, R3
#                                       placement, acknowledged publishing,
#                                       durable consumption
#   scripts/validate.sh --disruptive    additionally stops the stream leader's
#                                       server (service must continue), then
#                                       restarts ALL servers (data and consumer
#                                       position must survive).
#                                       TEST DEPLOYMENTS ONLY: it causes a
#                                       full outage of a few seconds.
SCRIPT_NAME=validate
# shellcheck source=scripts/lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
require_cmd docker

DISRUPTIVE=0
case "${1:-}" in
  "") ;;
  --disruptive) DISRUPTIVE=1 ;;
  *) die "usage: $0 [--disruptive]" ;;
esac

run="$(date -u +%Y%m%d%H%M%S)"
v() { nats_box app-admin sh /opt/nats-tools/validate.sh "$@"; }
cluster_healthy() { "$NATS_DIR/scripts/check-cluster.sh" --quiet >/dev/null 2>&1; }
trap 'v cleanup "$run" >/dev/null 2>&1 || true' EXIT

log "1/6 cluster membership, routes and quorum"
"$NATS_DIR/scripts/check-cluster.sh" || die "cluster is not fully healthy"
nats_box sys-admin server list

log "2/6 R3 placement of a file-backed stream"
v setup "$run"

log "3/6 acknowledged publishing + durable consumption"
v publish "$run" 200
v consume "$run" 100
v expect "$run" 200 100

if [ "$DISRUPTIVE" = 0 ]; then
  log "non-disruptive validation passed (use --disruptive on a TEST deployment for failover/restart)"
  exit 0
fi

leader="$(v leader "$run" | tail -n 1)"
case " $NATS_NODES " in *" $leader "*) ;; *) die "could not determine the stream leader" ;; esac
log "4/6 failover: stopping the stream leader $leader"
compose stop "$leader"
v publish "$run" 100
v consume "$run" 100
v expect "$run" 300 200
log "continued operation with $leader down: OK; starting it again"
compose start "$leader"
wait_until 300 "cluster fully healthy, $leader caught up" cluster_healthy || die "cluster did not recover"

log "5/6 persistence: restarting ALL servers"
compose restart nats-1 nats-2 nats-3
wait_until 300 "cluster fully healthy after full restart" cluster_healthy || die "cluster did not recover"
v expect "$run" 300 200

log "6/6 consume the rest after the restart"
v consume "$run" 100
v expect "$run" 300 300
log "disruptive validation passed"
