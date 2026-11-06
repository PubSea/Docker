#!/usr/bin/env bash
# Idempotently create/update the streams and consumers declared in ./jetstream
# (as app-admin, through the nats-box tools container) and verify that each
# one is placed on the requested number of servers with all replicas current.
# Safe to re-run at any time; see scripts/in-container/provision.sh.
SCRIPT_NAME=provision
# shellcheck source=scripts/lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
require_cmd docker

nats_box app-admin sh /opt/nats-tools/provision.sh /opt/jetstream
