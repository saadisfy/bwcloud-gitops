# Grafana Mimir – General Know-How & Explanation

## What is Grafana Mimir?
Grafana Mimir is an open-source, horizontally scalable, highly available, multi-tenant TSDB (Time Series Database) for long-term storage of Prometheus metrics. It allows you to store metrics reliably and execute PromQL queries over large volumes of data.

In our stack, Mimir serves as the primary metrics backend, receiving data pushed by Grafana Alloy (which acts as the collector/agent) and serving queries directly to Grafana.

## Core Concepts & Operations

### 1. High Availability & Scalability
Mimir is designed with a microservices architecture, where each component (distributor, ingester, querier, store-gateway, compactor) can be scaled independently based on the specific load (e.g., high write throughput vs. high query volume).
- Components use a **Hash Ring** (stored in a KV store) to coordinate work and ensure high availability without a single point of failure.

### 2. Multi-Tenancy
Mimir natively supports multi-tenancy. Every read and write request must contain an `X-Scope-OrgID` HTTP header identifying the tenant. Different tenants' data is logically isolated, and limits (e.g., max series per metric, max ingestion rate) can be enforced per tenant.

### 3. The Write Path
1. **Gateway**: Acts as the reverse proxy (often NGINX) routing incoming requests.
2. **Distributor**: Receives incoming metrics, validates them (e.g., checks against tenant limits, validates timestamps/labels), deduplicates if HA tracking is enabled, and hashes the labels to determine which Ingester should store the series.
3. **Ingester**: Receives the metrics from the distributor, writes them to a Write-Ahead Log (WAL) on disk for durability, and keeps the recent data (typically the last 2 hours) in memory (the "Head" block). Every 2 hours, it flushes this data into persistent TSDB blocks in object storage.

### 4. The Read Path
1. **Query Frontend**: Receives PromQL queries from Grafana. It splits large queries by time (e.g., into multiple 1-day queries) and caches results to speed up repeated queries.
2. **Querier**: Evaluates PromQL queries. It fetches recent, in-memory data directly from the **Ingesters**, and historical data from the **Store-Gateways**.
3. **Store-Gateway**: Keeps an index of the historical blocks stored in long-term storage (like S3, GCS, or in our case, the local filesystem) and fetches the required chunks on behalf of the Querier.
4. **Compactor**: Runs in the background to merge smaller 2-hour blocks into larger blocks (e.g., 12h or 24h), removing duplicates and reducing the index size for faster querying.

---

## Analysing Mimir Series and Cardinality

Controlling cardinality (the number of unique label combinations) is essential to keep Mimir performant. High cardinality leads to high memory usage in Ingesters and slow queries.

### 1. Identify Ingest Load (Rate-based)
Use these as your baseline:
- **Gateway request rate:** `sum(rate(nginx_http_requests_total[5m]))`
- **Distributor received samples rate:** `sum(rate(cortex_distributor_received_samples_total[5m]))`
- **Ingester active series:** `sum(cortex_ingester_active_series)`
- **Ingester in-memory series:** `sum(cortex_ingester_memory_series)`

*Interpretation:*
- Request rate indicates transport/API load.
- Received samples rate is the actual metric-point ingest load.
- Active/in-memory series represent TSDB pressure and memory footprint.

### 2. Cardinality Analysis

#### Top 15 Metrics by Active Series
This shows which metric names currently generate the most active time series.
```promql
topk(15, count by (__name__)({__name__!~"up|scrape_.*"}))
```

#### Top 15 Label Dimensions + Metric by Active Series
This helps identify which metric + label dimensions are cardinality drivers (e.g., unbounded labels like `path` or `uri`).
```promql
topk(
  15,
  sum by (label_name, __name__) (
    label_replace(count by (__name__, pod)({pod!="", __name__!~"up|scrape_.*"}), "label_name", "pod", "pod", ".*")
    or label_replace(count by (__name__, instance)({instance!="", __name__!~"up|scrape_.*"}), "label_name", "instance", "instance", ".*")
    or label_replace(count by (__name__, container)({container!="", __name__!~"up|scrape_.*"}), "label_name", "container", "container", ".*")
    or label_replace(count by (__name__, path)({path!="", __name__!~"up|scrape_.*"}), "label_name", "path", "path", ".*")
    or label_replace(count by (__name__, uri)({uri!="", __name__!~"up|scrape_.*"}), "label_name", "uri", "uri", ".*")
    or label_replace(count by (__name__, status)({status!="", __name__!~"up|scrape_.*"}), "label_name", "status", "status", ".*")
  )
)
```

### 3. What to Optimize First
1. High-cardinality labels with unbounded values (e.g., `path`, `uri`, request IDs).
2. Histogram explosion (`le` label combined with many dimensions).
3. Pod/container churn labels where not needed (e.g., ephemeral job IDs).
4. Duplicate ingestion paths.

### 4. Safe Optimization Playbook
1. Baseline current values (samples/s, active series, memory series).
2. Apply one relabel or instrumentation change in Grafana Alloy.
3. Compare before/after in 24h and 7d windows.
4. Keep changes if cardinality drops without losing critical SLO signals.
