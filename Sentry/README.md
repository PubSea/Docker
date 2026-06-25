docker network create shared_network

run docker composes related to Valkey, Kraft Kafka and Postgres

docker compose run --rm SnubaApi bootstrap --force

docker compose run --rm SentryUpgradeService

docker run --rm `
  -v ${PWD}\relay:/work/.relay `
  getsentry/relay:24.12.1 `
  credentials generate


