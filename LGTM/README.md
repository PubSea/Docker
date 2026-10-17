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

## 3. Latency percentiles (P50 … P99.99)

Latency percentiles come from Tempo's **span-metrics** (generated from the traces you send to Alloy) and are stored in Mimir.

- Tempo emits **native histograms** (`generate_native_histograms: both`), which keep high percentiles like P99.9 accurate (~5% max error). Mimir has native histogram ingestion enabled.
- The service label on span-metrics is **`service`** (not `service_name`).
- Query latency with the native histogram — no `_bucket` suffix and no `by (le)`:

```promql
histogram_quantile(0.999, sum(rate(traces_spanmetrics_latency{service="my-api"}[5m])))
```

- Dashboard: **LGTM → Service Latency Percentiles** (provisioned automatically).
- In a trace, click a span → *Related metrics* to see P50…P99.99 for that service.

> P99.9 needs at least ~1,000 requests in the window (5m) to be meaningful; with less traffic it is effectively the max.
