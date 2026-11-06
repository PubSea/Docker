#!/bin/sh
# Runs inside nats-box as app-admin (scripts/check-cluster.sh).
# Account-level JetStream usage + per-stream/consumer replica health.
# Prints Nagios-style lines; exit code = worst result (0 OK, 1 WARN, 2 CRIT).
set -u
worst=0
track() { [ "$1" -gt "$worst" ] && worst="$1"; return 0; }

out="$(nats server check jetstream --replicas --store-warn 75 --store-critical 90 \
  --mem-warn 75 --mem-critical 90 2>&1)"
rc=$?
echo "account APP: $out"
track "$rc"

streams="$(nats stream ls --names 2>/dev/null)" || {
  echo "streams: CRITICAL cannot list streams"
  exit 2
}
for s in $streams; do
  want="$(nats stream info "$s" --json 2>/dev/null | jq -r '.config.num_replicas // 1')"
  out="$(nats server check stream --stream "$s" --peer-expect "${want:-1}" \
    --peer-lag-critical 1000 --peer-seen-critical 10s 2>&1)"
  rc=$?
  echo "stream $s (R${want:-?}): $out"
  track "$rc"
  for c in $(nats consumer ls "$s" --names 2>/dev/null); do
    out="$(nats server check consumer --stream "$s" --consumer "$c" 2>&1)"
    rc=$?
    echo "consumer $s > $c: $out"
    track "$rc"
  done
done
exit "$worst"
