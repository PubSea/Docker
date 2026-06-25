# MinIO Setup Prerequisites

Before starting the MinIO, complete the following steps.

---

## 1. Create the Shared Docker Network

Create the external Docker network used by MinIO:

```bash
docker network create shared_network
```

> If the network already exists, Docker will return an error that can be safely ignored.

---