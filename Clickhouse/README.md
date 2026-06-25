# Clickhouse Setup Prerequisites

Before starting the Clickhouse, complete the following steps.

---

## 1. Create the Shared Docker Network

Create the external Docker network used by Clickhouse:

```bash
docker network create shared_network
```

> If the network already exists, Docker will return an error that can be safely ignored.

---