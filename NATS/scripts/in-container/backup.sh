#!/bin/sh
# Runs inside nats-box as app-admin (scripts/backup.sh).
# Online backup of every stream (and its consumers) of the APP account using
# the JetStream backup v2 API: no stream lock, publishing continues; each
# stream backup is a consistent point in time (= the recovery point).
set -eu
target="${1:?target directory}"

# Layout: <target>/streams/<STREAM>/{backup.json,stream.arc.s2}  (nats backup account)
#         <target>/MANIFEST.jsonl                                  (live positions)
# The streams/ directory must contain nothing but stream backups, otherwise
# `nats backup restore account` refuses it.
nats backup account "$target/streams" --consumers --force

# Offline integrity check of what was written (format, sequences, consumers).
for b in "$target"/streams/*/; do
  [ -f "$b/backup.json" ] || continue
  nats backup validate "$b" --no-progress
done

# Manifest of the live state right after the backup, used by restore drills
# to cross-check consumer positions (informational if traffic continued).
for s in $(nats stream ls --names); do
  nats stream info "$s" --json | jq -c '{stream: .config.name, replicas: .config.num_replicas, state: .state}'
  for c in $(nats consumer ls "$s" --names); do
    nats consumer info "$s" "$c" --json |
      jq -c '{stream: .stream_name, consumer: .name, delivered: .delivered, ack_floor: .ack_floor, num_pending: .num_pending, num_ack_pending: .num_ack_pending}'
  done
done >"$target/MANIFEST.jsonl"
echo "backup complete: $target"
