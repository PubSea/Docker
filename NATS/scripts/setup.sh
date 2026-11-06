#!/usr/bin/env bash
# One-time, idempotent bootstrap of the NATS stack. Safe to re-run.
#   1. .env from .env.example + the host UID/GID the containers run as
#   2. private CA and node certificates      (scripts/pki.sh)
#   3. user passwords and bcrypt hash file    (scripts/credentials.sh)
#   4. probe: can a container running as that UID read the 0600 secrets and
#      write ./backups through bind mounts? (Docker Desktop for Mac file
#      sharing may present bind-mounted files as root-owned)
#   5. sanity checks (shared_network, compose file)
# Run it as the non-root user that operates the stack, from any directory.
SCRIPT_NAME=setup
# shellcheck source=scripts/lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
require_cmd docker openssl

docker compose version >/dev/null 2>&1 || die "Docker Compose v2 plugin is required"

ensure_env_file
"$NATS_DIR/scripts/pki.sh"
"$NATS_DIR/scripts/credentials.sh"

mkdir -p "$NATS_DIR/backups"
chmod 700 "$NATS_DIR/backups"

# A container running as $1:$2 without any capability must be able to read a
# 0600 secret and write into ./backups via bind mounts, exactly like the
# servers and the tools container will.
probe_identity() {
  docker run --rm --network none --user "$1:$2" --cap-drop ALL \
    --security-opt no-new-privileges:true \
    -v "$NATS_DIR/secrets/server/credentials.conf:/probe/secret:ro" \
    -v "$NATS_DIR/certs/nats-1/server.key:/probe/key:ro" \
    -v "$NATS_DIR/backups:/probe/backups" \
    --entrypoint sh "$(service_image nats-1)" \
    -c 'cat /probe/secret /probe/key >/dev/null && touch /probe/backups/.probe && rm -f /probe/backups/.probe' \
    >/dev/null 2>&1
}
uid="$(env_get NATS_UID)"
gid="$(env_get NATS_GID)"
if probe_identity "$uid" "$gid"; then
  log "bind-mount probe ok: containers run as $uid:$gid"
elif probe_identity 0 0; then
  # Docker Desktop's file sharing (VirtioFS) can show bind-mounted files as
  # owned by root; only root in the container can then read 0600 files.
  # Containers still run without capabilities, read-only, no-new-privileges.
  tmp="$(mktemp "$NATS_DIR/.env.XXXXXX")"
  grep -v -e '^NATS_UID=' -e '^NATS_GID=' "$NATS_DIR/.env" >"$tmp" || true
  printf 'NATS_UID=0\nNATS_GID=0\n' >>"$tmp"
  cat "$tmp" >"$NATS_DIR/.env"
  rm -f "$tmp"
  warn "UID $uid cannot read bind-mounted secrets (typical for Docker Desktop file sharing);"
  warn "containers will run as UID 0 with all capabilities dropped (NATS_UID=0 in .env)."
else
  die "no container identity can read ./secrets or write ./backups: check Docker's file sharing settings for $NATS_DIR"
fi

if ! docker network inspect shared_network >/dev/null 2>&1; then
  warn "external network shared_network does not exist yet. Create it once with:"
  warn "  docker network create shared_network"
fi

compose --profile tools config --quiet
log "docker-compose.yaml is valid"
log "next: docker compose up -d && scripts/check-cluster.sh && scripts/provision-jetstream.sh"
