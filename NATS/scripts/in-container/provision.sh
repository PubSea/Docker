#!/bin/sh
# Runs inside the nats-box container as app-admin (scripts/provision-jetstream.sh).
# Idempotently creates or reconciles the JetStream assets declared in
# /opt/jetstream (= ./jetstream on the host):
#   streams/<STREAM>.json                  stream config (JetStream API JSON)
#   consumers/<STREAM>/<CONSUMER>.json     durable consumer config
#
# * Missing asset            -> created.
# * Existing, same config    -> no-op (re-running is safe).
# * Existing, changed config -> edited in place. Immutable fields (name,
#   storage type, ...) make the edit fail loudly instead of being guessed.
# Afterwards every asset must report the requested replica count on distinct
# servers, all current, or the script fails.
set -eu
JS_DIR="${1:-/opt/jetstream}"
TIMEOUT="${PROVISION_TIMEOUT:-60}"

say() { printf '[provision] %s\n' "$*"; }

for f in "$JS_DIR"/streams/*.json; do
  [ -e "$f" ] || continue
  name="$(jq -er .name "$f")"
  if nats stream info "$name" --json >/dev/null 2>&1; then
    say "stream $name exists: reconciling with $(basename "$f")"
    nats stream edit "$name" --config "$f" --force >/dev/null
  else
    say "stream $name: creating from $(basename "$f")"
    nats stream add "$name" --config "$f" >/dev/null
  fi
done

for f in "$JS_DIR"/consumers/*/*.json; do
  [ -e "$f" ] || continue
  stream="$(basename "$(dirname "$f")")"
  name="$(jq -er .durable_name "$f")"
  if nats consumer info "$stream" "$name" --json >/dev/null 2>&1; then
    say "consumer $stream > $name exists: reconciling with $(basename "$f")"
    nats consumer edit "$stream" "$name" --config "$f" --force >/dev/null
  else
    say "consumer $stream > $name: creating from $(basename "$f")"
    nats consumer add "$stream" --config "$f" >/dev/null
  fi
done

# --- Verify placement ---------------------------------------------------------
# A clustered server does NOT make a stream replicated: num_replicas decides.
# Check that each asset really has N distinct peers and that all are current.
placement_ok() { # $1 = info JSON, $2 = wanted replicas
  printf '%s' "$1" | jq -e --argjson want "$2" '
    (.cluster.leader // "") as $l
    | (.cluster.replicas // []) as $r
    | $l != "" and ([$l] + [$r[].name] | unique | length) == $want
      and ([$r[] | select(.current != true)] | length) == 0' >/dev/null
}

wait_placement() { # $1 = label, $2 = wanted, $3.. = nats command printing JSON
  label="$1"
  want="$2"
  shift 2
  deadline=$(($(date +%s) + TIMEOUT))
  while :; do
    info="$("$@" 2>/dev/null || true)"
    if [ -n "$info" ] && placement_ok "$info" "$want"; then
      say "OK   $label: R$want leader=$(printf '%s' "$info" | jq -r .cluster.leader) followers=$(printf '%s' "$info" | jq -r '[.cluster.replicas[].name] | join(",")')"
      return 0
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      say "FAIL $label: expected $want current replicas within ${TIMEOUT}s; cluster state:"
      printf '%s' "$info" | jq -c '.cluster' >&2 || true
      return 1
    fi
    sleep 2
  done
}

rc=0
for f in "$JS_DIR"/streams/*.json; do
  [ -e "$f" ] || continue
  name="$(jq -er .name "$f")"
  want="$(jq -r '.num_replicas // 1' "$f")"
  wait_placement "stream $name" "$want" nats stream info "$name" --json || rc=1
done
for f in "$JS_DIR"/consumers/*/*.json; do
  [ -e "$f" ] || continue
  stream="$(basename "$(dirname "$f")")"
  name="$(jq -er .durable_name "$f")"
  want="$(jq -r '.num_replicas // 0' "$f")"
  if [ "$want" = 0 ]; then # inherits the stream's replica count
    want="$(nats stream info "$stream" --json | jq -r .config.num_replicas)"
  fi
  wait_placement "consumer $stream > $name" "$want" nats consumer info "$stream" "$name" --json || rc=1
done
exit "$rc"
