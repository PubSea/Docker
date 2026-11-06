#!/usr/bin/env bash
# Load monitoring/nats-alerts.yml into the Mimir ruler of the LGTM stack.
# Idempotent: the "nats" namespace is replaced with the content of the file.
#
#   scripts/load-alert-rules.sh                 check + unit-test + load
#   scripts/load-alert-rules.sh --check-only    no network access to Mimir
#
# Defaults match LGTM/docker-compose.yaml (Mimir at mimir:9009 on
# shared_network, multitenancy disabled => tenant "anonymous"). Override with
# MIMIR_ADDRESS / MIMIR_TENANT. Grafana shows the rules under
# Alerting > Alert rules > Data source-managed (Mimir). Mimir in -target=all
# mode evaluates them; to send notifications configure an Alertmanager for the
# ruler (README "Alerting").
SCRIPT_NAME=alert-rules
# shellcheck source=scripts/lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
require_cmd docker

MIMIRTOOL_IMAGE="${MIMIRTOOL_IMAGE:-grafana/mimirtool:2.17.11@sha256:7780cd9aa0c4618af5c0faa90a2e148b517221aaa5703dc279a46024b1421838}"
PROMTOOL_IMAGE="${PROMTOOL_IMAGE:-prom/prometheus:v3.8.1@sha256:2b6f734e372c1b4717008f7d0a0152316aedd4d13ae17ef1e3268dbfaf68041b}"
MIMIR_ADDRESS="${MIMIR_ADDRESS:-http://mimir:9009}"
MIMIR_TENANT="${MIMIR_TENANT:-anonymous}"
MON="$NATS_DIR/monitoring"

# Run the tool containers as the identity that can read this checkout's files
# (NATS_UID/NATS_GID from .env, chosen by scripts/setup.sh), never as the
# image default (prom/prometheus runs as "nobody" and cannot read 0600 files).
uid="$(env_get NATS_UID)"
gid="$(env_get NATS_GID)"
RUN_AS="${uid:-$(id -u)}:${gid:-$(id -g)}"

docker run --rm --network none --user "$RUN_AS" -v "$MON:/rules:ro" "$MIMIRTOOL_IMAGE" \
  rules check /rules/nats-alerts.yml
docker run --rm --network none --user "$RUN_AS" -v "$MON:/rules:ro" -w /rules --entrypoint promtool "$PROMTOOL_IMAGE" \
  test rules nats-alerts.test.yml
[ "${1:-}" = "--check-only" ] && exit 0

# The namespace is taken from the "namespace" key mimirtool expects; inject it
# into a temporary copy so the tracked file stays plain Prometheus format.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
{
  echo "namespace: nats"
  cat "$MON/nats-alerts.yml"
} >"$tmp/nats.yml"
chmod 755 "$tmp"
chmod 644 "$tmp/nats.yml"
# --namespaces=nats confines the sync to this namespace: rules other teams
# loaded into Mimir are never modified or deleted.
docker run --rm --network shared_network --user "$RUN_AS" -v "$tmp:/load:ro" "$MIMIRTOOL_IMAGE" \
  rules sync --address "$MIMIR_ADDRESS" --id "$MIMIR_TENANT" --namespaces nats /load/nats.yml
docker run --rm --network shared_network "$MIMIRTOOL_IMAGE" \
  rules list --address "$MIMIR_ADDRESS" --id "$MIMIR_TENANT"
