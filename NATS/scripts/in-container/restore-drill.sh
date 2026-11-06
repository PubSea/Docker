#!/bin/sh
# Runs inside nats-box against the THROWAWAY drill server started by
# scripts/restore-drill.sh (never against the cluster).
# For every stream backup in $1/streams (layout written by scripts/backup.sh):
#   1. offline validation of the archive
#   2. restore (single replica: the drill server is one node)
#   3. compare the restored stream with what the backup contains
#   4. check every consumer came back, and read the first and last message
set -eu
dir="${1:?backup directory}"
fail=0
streams=0
say() { printf '[drill] %s\n' "$*"; }
bad() {
  say "FAIL $*"
  fail=1
}

for b in "$dir"/streams/*/; do
  [ -f "$b/backup.json" ] || continue
  name="$(jq -r .config.name "$b/backup.json")"
  streams=$((streams + 1))
  say "---- stream $name ($b)"

  if ! nats backup validate "$b" --no-progress >/dev/null; then
    bad "$name: archive does not validate"
    continue
  fi
  expected="$(nats backup info "$b" --json --no-progress)"

  if ! nats backup restore stream "$b" --replicas 1 --no-progress >/dev/null; then
    bad "$name: restore failed"
    continue
  fi
  got="$(nats stream info "$name" --json)"

  for field in messages first_seq last_seq; do
    e="$(printf '%s' "$expected" | jq -r ".$field")"
    g="$(printf '%s' "$got" | jq -r ".state.$field")"
    if [ "$e" = "$g" ]; then say "OK   $name $field=$g"; else bad "$name $field: backup=$e restored=$g"; fi
  done
  say "info $name bytes: backup=$(printf '%s' "$expected" | jq -r .bytes) restored=$(printf '%s' "$got" | jq -r .state.bytes)"

  for c in $(printf '%s' "$expected" | jq -r '.consumers[]?'); do
    if info="$(nats consumer info "$name" "$c" --json 2>/dev/null)"; then
      floor="$(printf '%s' "$info" | jq -r .ack_floor.stream_seq)"
      say "OK   $name > $c restored: $(printf '%s' "$info" | jq -c '{ack_floor: .ack_floor.stream_seq, delivered: .delivered.stream_seq, num_pending}')"
      # Cross-check with the live position recorded right after the backup.
      # Only informational: consumers may have acked more during the backup.
      if [ -f "$dir/MANIFEST.jsonl" ]; then
        live="$(jq -r --arg s "$name" --arg c "$c" 'select(.stream == $s and .consumer == $c) | .ack_floor.stream_seq' "$dir/MANIFEST.jsonl" | head -n 1)"
        if [ -n "$live" ] && [ "$live" != "$floor" ]; then
          say "warn $name > $c ack floor: restored=$floor, live after backup=$live (acks during backup?)"
        fi
      fi
    else
      bad "$name > $c: consumer missing after restore"
    fi
  done

  first="$(printf '%s' "$got" | jq -r .state.first_seq)"
  last="$(printf '%s' "$got" | jq -r .state.last_seq)"
  if [ "$(printf '%s' "$got" | jq -r .state.messages)" -gt 0 ]; then
    if nats stream get "$name" "$first" >/dev/null 2>&1 && nats stream get "$name" "$last" >/dev/null 2>&1; then
      say "OK   $name messages $first and $last are readable"
    else
      bad "$name: could not read message $first or $last"
    fi
  fi
done

[ "$streams" -gt 0 ] || bad "no stream backups found under $dir/streams"
if [ "$fail" = 0 ]; then say "RESULT: PASS - backup $dir is restorable"; else say "RESULT: FAIL"; fi
exit "$fail"
