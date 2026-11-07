#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

docker compose up -d --wait --wait-timeout 300 mysql-1 mysql-2 mysql-3
docker compose run --rm --no-deps cluster-init
docker compose up -d --build --wait --wait-timeout 120 mysql-router
