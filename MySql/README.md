# MySQL InnoDB Cluster

Three MySQL **26.10.0 Innovation** members in single-primary mode, bootstrapped
with MySQL Shell, plus MySQL Router **26.10.0**. Images are version-pinned.
Router is built locally for `linux/arm64` on Oracle Linux 9 using the official
Oracle MySQL Router RPM with signature verification enabled. Both Router and
MySQL Server run natively on Apple Silicon, without amd64 emulation.
The Dockerfile pins Router to 26.10.0; the base OS receives current OL9 updates.

Latest GA release checked on 2026-11-07:
https://dev.mysql.com/doc/relnotes/mysql/26.10/en/news-26-10-0.html

## Start

```bash
cd MySql
cp .env.example .env # first setup only; choose passwords before startup
# Only if the project's external network does not already exist:
docker network inspect shared_network >/dev/null 2>&1 || docker network create shared_network
./start.sh
```

`./start.sh` starts the nodes and waits for health, runs initialization with
`docker compose run --rm`, then starts Router. The temporary init container is
automatically removed on exit (including failure); its output is shown in the
terminal. A failed initialization stops the script before starting Router.
The `tools` profile keeps `cluster-init` out of normal `docker compose up`.
Use `./start.sh` for first setup; plain `docker compose up` does not initialize
a new cluster.

Initialization waits for healthy nodes, creates `pubsea`, clones the two
secondaries, and creates application database/user `pubsea`. Data is persisted
in three separate named volumes. Re-running initialization preserves membership
and data. Changing `.env` passwords does not rotate existing database accounts.

## Connect

| Client | Read/write | Read-only |
| --- | --- | --- |
| Host machine | `127.0.0.1:6446` | `127.0.0.1:6447` |
| Containers on `shared_network` | `mysql-router:6446` | `mysql-router:6447` |

Database and user: `pubsea`. Password: `MYSQL_APP_PASSWORD` in `.env`.
Host ports can be changed in `.env`. Members use a separate Docker network;
only Router joins the project's shared network. Host ports bind to loopback.

## Verify

```bash
docker compose ps -a
docker compose run --rm --no-deps --entrypoint mysqlsh cluster-init --no-defaults --js --file /scripts/verify.js
```

The verification fails unless all three members are ONLINE, the cluster status
is OK, Router sends writes to the primary and reads to a secondary, and an
insert is replicated. It removes its inserted row afterwards.

## Stop and recover

```bash
docker compose stop
```

A single failed member normally rejoins automatically. For a complete cluster
outage, start the members, then explicitly recover with Shell (without forcing
quorum or discarding transactions):

```bash
docker compose up -d mysql-1 mysql-2 mysql-3
docker compose run --rm --no-deps --entrypoint mysqlsh cluster-init --no-defaults --js --uri root@mysql-1:3306
# Enter MYSQL_ROOT_PASSWORD, then at the JavaScript prompt:
# dba.rebootClusterFromCompleteOutage('pubsea')
# \quit
./start.sh
```

If Shell identifies a different member as the freshest GTID seed, connect to
that member and follow its recovery guidance. Do not use `force` by default.
`docker compose down` preserves data; `docker compose down -v` deletes it.

This is a local development cluster on one Docker host. It tolerates one MySQL
member failure, but not failure of the host or the single Router. Use separate
hosts, redundant routers, backups, and managed secrets for production.
