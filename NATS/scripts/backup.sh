#!/usr/bin/env bash
# Online backup of every JetStream stream (with consumer state) of the APP
# account into ./backups/<UTC timestamp>/, validated right after writing.
#
#   scripts/backup.sh
#
# Options (env or .env):
#   NATS_BACKUP_KEEP=7          local backups to keep (older ones are deleted)
#   NATS_BACKUP_REMOTE=remote:path
#                               also copy the backup off this host with rclone
#                               (remote defined in secrets/rclone.conf, see
#                               README "Backup storage")
#
# A backup that only exists on this Docker host does not survive the loss of
# this host: configure NATS_BACKUP_REMOTE and run scripts/restore-drill.sh
# regularly. Schedule with cron/launchd, e.g. 15 2 * * * /path/to/NATS/scripts/backup.sh
SCRIPT_NAME=backup
# shellcheck source=scripts/lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
require_cmd docker

ts="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$NATS_DIR/backups"
chmod 700 "$NATS_DIR/backups"

log "backing up all streams to backups/$ts"
nats_box app-admin sh /opt/nats-tools/backup.sh "/backups/$ts"
log "local backup ok: backups/$ts ($(du -sh "$NATS_DIR/backups/$ts" | cut -f1))"

remote="${NATS_BACKUP_REMOTE:-$(env_get NATS_BACKUP_REMOTE)}"
if [ -n "$remote" ]; then
  [ -s "$NATS_DIR/secrets/rclone.conf" ] || die "NATS_BACKUP_REMOTE is set but secrets/rclone.conf is missing"
  log "copying backups/$ts to $remote/$ts"
  compose run --rm --no-deps -T backup-sync copy "/backups/$ts" "$remote/$ts" --checksum --immutable
  compose run --rm --no-deps -T backup-sync check "/backups/$ts" "$remote/$ts" --one-way
  log "off-host copy verified: $remote/$ts"
fi

keep="${NATS_BACKUP_KEEP:-$(env_get NATS_BACKUP_KEEP)}"
keep="${keep:-7}"
# shellcheck disable=SC2012 # timestamp-named directories only
list="$(ls -1d "$NATS_DIR"/backups/[0-9]*T[0-9]*Z 2>/dev/null | sort || true)"
count="$(printf '%s\n' "$list" | grep -c . || true)"
if [ "$count" -gt "$keep" ]; then
  printf '%s\n' "$list" | head -n $((count - keep)) | while IFS= read -r old; do
    log "retention: deleting local $(basename "$old") (keeping $keep)"
    rm -rf "$old"
  done
fi
