# Kafka cluster Setup Prerequisites

Before starting the kafka cluster, complete the following steps.

---

## 1. Create the Shared Docker Network

Create the external Docker network used by Kafka:

```bash
docker network create shared_network
```

> If the network already exists, Docker will return an error that can be safely ignored.

if this error occurred "The node is not formatted" run the following command

```bash
docker run --rm apache/kafka:4.3.0 kafka-storage.sh format --cluster-id HsDBs9l6UUmQq7Y5E6bNlw --config /opt/kafka/config/kraft/server.properties
```

---