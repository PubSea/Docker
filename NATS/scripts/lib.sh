#!/usr/bin/env bash
# Shared helpers for the NATS stack scripts. Sourced, not executed.
# Portable to the bash 3.2 that ships with macOS (no associative arrays,
# no mapfile, no ${var,,}).
# shellcheck shell=bash

set -o errexit -o nounset -o pipefail

NATS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034 # used by the scripts that source this file
NATS_NODES="nats-1 nats-2 nats-3"
: "${SCRIPT_NAME:=nats}"

log() { printf '%s [%s] %s\n' "$(date -u +%H:%M:%SZ)" "$SCRIPT_NAME" "$*" >&2; }
warn() { log "WARNING: $*"; }
die() {
  log "ERROR: $*"
  exit 1
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
  done
}

# docker compose bound to this directory, independent of the caller's cwd.
compose() {
  docker compose --project-directory "$NATS_DIR" -f "$NATS_DIR/docker-compose.yaml" "$@"
}

# Value of KEY in .env (empty if unset).
env_get() {
  [ -f "$NATS_DIR/.env" ] || return 0
  sed -n "s/^$1=//p" "$NATS_DIR/.env" | tail -n 1
}

# Create .env from .env.example and record the host UID/GID that owns the
# generated secrets. The NATS containers run as this (non-root) UID so they can
# read 0600 secret files without extra capabilities.
ensure_env_file() {
  local uid gid tmp
  if [ ! -f "$NATS_DIR/.env" ]; then
    cp "$NATS_DIR/.env.example" "$NATS_DIR/.env"
    log "created .env from .env.example"
  fi
  uid="$(id -u)"
  gid="$(id -g)"
  if [ "$uid" = "0" ]; then
    warn "running as root: secrets will be owned by root and the containers will run as root."
    warn "Run the scripts as the (non-root) user that operates this stack instead."
  fi
  if [ "$(env_get NATS_UID)" != "$uid" ] || [ "$(env_get NATS_GID)" != "$gid" ]; then
    tmp="$(mktemp "$NATS_DIR/.env.XXXXXX")"
    grep -v -e '^NATS_UID=' -e '^NATS_GID=' "$NATS_DIR/.env" >"$tmp" || true
    printf 'NATS_UID=%s\nNATS_GID=%s\n' "$uid" "$gid" >>"$tmp"
    cat "$tmp" >"$NATS_DIR/.env"
    rm -f "$tmp"
    log "set NATS_UID=$uid NATS_GID=$gid in .env"
  fi
}

# Image reference (tag@digest) Compose resolves for a service.
service_image() {
  compose --profile tools config --images "$1" | head -n 1
}

# Run the nats CLI in the throwaway nats-box tools container as one of the
# stack identities (sys-admin | app-admin | orders-publisher | orders-consumer).
# The password is read from a Compose secret inside the container, so it never
# appears in argv, `docker inspect`, or shell history.
#   nats_box app-admin stream ls
#   nats_box app-admin sh /opt/nats-tools/provision.sh
nats_box() {
  mkdir -p "$NATS_DIR/backups"
  compose run --rm --no-deps -T nats-box "$@"
}

# GET a monitoring endpoint of one node from inside that node's container.
# The monitoring port only listens on the private cluster network.
node_monitor() {
  local node="$1" path="$2"
  # shellcheck disable=SC2016 # expanded inside the container
  compose exec -T "$node" sh -c 'wget -q -T 3 -O - "http://${NATS_MONITOR_ADDR}$1"' _ "$path"
}

# Retry "$@" until it succeeds or TIMEOUT seconds pass.
wait_until() {
  local timeout="$1" desc="$2" start
  shift 2
  start="$(date +%s)"
  until "$@" >/dev/null 2>&1; do
    if [ $(($(date +%s) - start)) -ge "$timeout" ]; then
      warn "timed out after ${timeout}s waiting for: $desc"
      return 1
    fi
    sleep 2
  done
  log "ok: $desc"
}
