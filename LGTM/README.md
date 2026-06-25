# LGTM stack Setup Prerequisites

Before starting the LGTM stack, complete the following steps.

---

## 1. Create the Shared Docker Network

Create the external Docker network used by LGTM stack:

```bash
docker network create shared_network
```

> If the network already exists, Docker will return an error that can be safely ignored.


## 2. Create these buckets in Object storage
#### loki
#### tempo
#### mimir-alertmanager
#### mimir-ruler
#### mimir-blocks
---