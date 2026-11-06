#!/usr/bin/env bash
# Three levels of health, deliberately kept apart:
#
#   liveness   process up, JetStream enabled  /healthz?js-enabled-only=true
#              (this is the Docker healthcheck; it ignores peers on purpose)
#   quorum     this node sees a JetStream meta leader and is current with it
#                                             /healthz?js-meta-only=true
#   ready      quorum + every stream/consumer replica on this node is current
#                                             /healthz
#
# plus cluster-wide checks through the nats CLI (meta group membership, account
# limits, replica health of every stream and consumer).
#
# Exit codes: 0 healthy | 1 degraded: quorum intact but a server or replica is
# down/behind | 2 critical: no meta quorum, writes to replicated streams stop.
#   scripts/check-cluster.sh            human readable
#   scripts/check-cluster.sh --quiet    only the RESULT line (for scripts/cron)
SCRIPT_NAME=check
# shellcheck source=scripts/lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
require_cmd docker
set +o errexit

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
say() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }

probe() { # node path -> prints HTTP-ish status word
  if node_monitor "$1" "$2" >/dev/null 2>&1; then echo ok; else echo FAIL; fi
}

say "NATS cluster check $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "$(printf '%-8s %-10s %-9s %-7s %-7s %s' node container liveness quorum ready routes-to)"
up=0
quorum_seen=0
for node in $NATS_NODES; do
  state="$(docker inspect -f '{{.State.Status}}' "$node" 2>/dev/null || echo missing)"
  if [ "$state" != running ]; then
    say "$(printf '%-8s %-10s %-9s %-7s %-7s %s' "$node" "$state" - - - -)"
    continue
  fi
  live="$(probe "$node" '/healthz?js-enabled-only=true')"
  meta="$(probe "$node" '/healthz?js-meta-only=true')"
  ready="$(probe "$node" '/healthz')"
  routes="$(node_monitor "$node" /routez 2>/dev/null | grep -o '"remote_name": *"[^"]*"' |
    sed 's/.*"\([^"]*\)"$/\1/' | sort -u | tr '\n' ',' | sed 's/,$//')"
  [ "$live" = ok ] && up=$((up + 1))
  [ "$meta" = ok ] && quorum_seen=1
  say "$(printf '%-8s %-10s %-9s %-7s %-7s %s' "$node" "$state" "$live" "$meta" "$ready" "${routes:--}")"
done

worst=0
if [ "$up" -gt 0 ]; then
  meta_out="$(nats_box sys-admin server check meta --expect 3 --lag-critical 1000 --seen-critical 10s 2>/dev/null)"
  meta_rc=$?
  say "meta group: ${meta_out:-CRITICAL no answer from the cluster}"
  [ -n "$meta_out" ] || meta_rc=2
  [ "$meta_rc" -gt "$worst" ] && worst=$meta_rc

  js_out="$(nats_box app-admin sh /opt/nats-tools/check-streams.sh 2>/dev/null)"
  js_rc=$?
  say "${js_out:-streams: CRITICAL no answer from the cluster}"
  [ -n "$js_out" ] || js_rc=2
  [ "$js_rc" -gt "$worst" ] && worst=$js_rc
fi

if [ "$quorum_seen" = 0 ]; then
  result=2
  msg="CRITICAL - no JetStream meta quorum ($up/3 servers live): writes to replicated streams are blocked"
elif [ "$up" -lt 3 ] || [ "$worst" -gt 0 ]; then
  result=1
  msg="DEGRADED - quorum intact ($up/3 servers live) but redundancy is reduced; see lines above"
else
  result=0
  msg="OK - 3/3 servers live, meta quorum and all replicas current"
fi
printf 'RESULT: %s\n' "$msg"
exit "$result"
