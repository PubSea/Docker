# ValKey Setup Prerequisites

Before starting the ValKey, complete the following steps.

---

## 1. Create the Shared Docker Network

Create the external Docker network used by ValKey:

```bash
docker network create shared_network
```

> If the network already exists, Docker will return an error that can be safely ignored.

---