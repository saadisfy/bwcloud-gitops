# How to analyse Mimir series and cardinality

This guide explains a practical workflow to analyze:
- ingest load into Mimir,
- active and in-memory series growth,
- cardinality hotspots (which metrics/labels create most series).

## 1) Start with ingestion flow (rate-based)

Use these as your baseline:

- **Gateway request rate**
  - `sum(rate(nginx_http_requests_total[5m]))`
- **Distributor received samples rate**
  - `sum(rate(cortex_distributor_received_samples_total[5m]))`
- **Ingester active series**
  - `sum(cortex_ingester_active_series)`
- **Ingester in-memory series**
  - `sum(cortex_ingester_memory_series)`

Interpretation:
- Request rate is transport/API load.
- Received samples rate is actual metric-point ingest load.
- Active/in-memory series represent TSDB pressure and memory footprint.

## 2) Analyse Grafana Alloy load (input vs output)

For Alloy, focus on OpenTelemetry internal metrics:

- **Incoming from scrape receiver**
  - `sum(rate(otelcol_receiver_accepted_metric_points{receiver=~"prometheus.*"}[5m]))`
- **Incoming from OTLP receiver**
  - `sum(rate(otelcol_receiver_accepted_metric_points{receiver=~"otlp.*"}[5m]))`
- **Outgoing to Mimir**
  - `sum(rate(otelcol_exporter_sent_metric_points{exporter=~"otlphttp.*|mimir.*"}[5m]))`
- **Exporter failures**
  - `sum(rate(otelcol_exporter_send_failed_metric_points{exporter=~"otlphttp.*|mimir.*"}[5m]))`

Useful checks:
- If incoming >> outgoing for a sustained period, check batching/queue/backpressure.
- Any non-zero exporter failures should be investigated.

## 3) Conversion factors (estimation only)

There is no strict 1:1 conversion between gateway metrics and series counts.
Use estimators:

- **Samples per request**
  - `sum(rate(cortex_distributor_received_samples_total[5m])) / clamp_min(sum(rate(nginx_http_requests_total[5m])), 1)`
- **Samples per active connection per second**
  - `sum(rate(cortex_distributor_received_samples_total[5m])) / clamp_min(sum(nginx_connections_active), 1)`

Series estimation:
- `active_series ~ received_samples_rate * scrape_interval_seconds`
- `memory_series ~ active_series * memory_overhead_factor`

Treat these as directional estimates, not exact accounting.

## 4) Cardinality analysis

## Top 15 metrics by active series

```promql
topk(15, count by (__name__)({__name__!~"up|scrape_.*"}))
```

This shows which metric names currently generate the most active time series.

## Top 15 label dimensions + metric by active series

```promql
topk(
  15,
  sum by (label_name, __name__) (
    label_replace(count by (__name__, pod)({pod!="", __name__!~"up|scrape_.*"}), "label_name", "pod", "pod", ".*")
    or label_replace(count by (__name__, instance)({instance!="", __name__!~"up|scrape_.*"}), "label_name", "instance", "instance", ".*")
    or label_replace(count by (__name__, container)({container!="", __name__!~"up|scrape_.*"}), "label_name", "container", "container", ".*")
    or label_replace(count by (__name__, path)({path!="", __name__!~"up|scrape_.*"}), "label_name", "path", "path", ".*")
    or label_replace(count by (__name__, uri)({uri!="", __name__!~"up|scrape_.*"}), "label_name", "uri", "uri", ".*")
    or label_replace(count by (__name__, le)({le!="", __name__!~"up|scrape_.*"}), "label_name", "le", "le", ".*")
    or label_replace(count by (__name__, method)({method!="", __name__!~"up|scrape_.*"}), "label_name", "method", "method", ".*")
    or label_replace(count by (__name__, status)({status!="", __name__!~"up|scrape_.*"}), "label_name", "status", "status", ".*")
  )
)
```

This helps identify which metric + label dimensions are cardinality drivers.

## 5) What to optimize first

1. High-cardinality labels with unbounded values (`path`, `uri`, request IDs, user IDs).
2. Histogram explosion (`le` + many dimensions).
3. Pod/container churn labels where not needed.
4. Duplicate ingestion paths (same metric via multiple receivers).

## 6) Safe optimization playbook

1. Baseline current values (samples/s, active series, memory series).
2. Apply one relabel or instrumentation change.
3. Compare before/after in 24h and 7d windows.
4. Keep changes if cardinality drops without losing critical SLO signals.

## 7) Dashboard reference

Use dashboard:
- [docs/dashboards/mimir-series-flow-dashboard.json](docs/dashboards/mimir-series-flow-dashboard.json)

It includes:
- Mimir series flow,
- Alloy incoming/outgoing load,
- conversion estimators,
- cardinality analysis row (last row).
