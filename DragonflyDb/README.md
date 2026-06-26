# DragonflyDb Setup Prerequisites

Before starting the DragonflyDb, complete the following steps.

---

## 1. Create the Shared Docker Network

Create the external Docker network used by DragonflyDb:

```bash
docker network create shared_network
```

> If the network already exists, Docker will return an error that can be safely ignored.

DragonflyDb is designed to scale up not scale out and is very compatible with k8s.
It would not handle failover automatically so the best option is to run it on k8s clusters to handle this problem.
---