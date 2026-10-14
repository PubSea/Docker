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
> Change object storage service name and its related port, $\color{#ff7}{access key}$ and $\color{#ff7}{secret}$ in whole project according to your object storage credentials.
> If you use SeaWeedFs and there is no folder with name buckets by default you have to create this folder exactly with this name then create the following folders inside it!
#### loki
#### tempo
#### mimir-alertmanager
#### mimir-ruler
#### mimir-blocks
---