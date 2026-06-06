# LGTM-Korrelation: Implementierung (Noctua)

Konkrete GitOps-Änderungen für die offenen Punkte. Basiert auf Skills:
`.gemini/skills/tempo`, `.gemini/skills/dashboarding`, `.agents/skills/otel-collector`, `.agents/skills/otel-instrumentation`.

---

## 1. OTel Java: Logs per OTLP aktivieren

**Problem:** Alloy filtert stdout-Logs für OTel-injizierte Pods (`otel_injected != nil`), aber `OTEL_LOGS_EXPORTER=none` → keine Logs in Loki.

**Datei:** [`apps/otel-operator/noctua/templates/instrumentation-java.yaml`](../../../apps/otel-operator/noctua/templates/instrumentation-java.yaml)

```yaml
spec:
  env:
    - name: OTEL_LOGS_EXPORTER
      value: "otlp"
    - name: OTEL_TRACES_EXPORTER
      value: "otlp"
    - name: OTEL_METRICS_EXPORTER
      value: "otlp"
    - name: OTEL_INSTRUMENTATION_RUNTIME_METRICS_ENABLED
      value: "true"
  resource:
    resourceAttributes:
      deployment.environment.name: noctua
```

---

## 1b. OTLP via Alloy + Exemplars (Produktiv-Pfad)

**Ziel:** Spring Petclinic (und andere OTel-injizierte Apps) senden OTLP an **Grafana Alloy** (`applicationObservability` auf `alloy-node`), nicht an den separaten `otel-collector`.

**Datei:** [`apps/otel-operator/noctua/values.yaml`](../../../apps/otel-operator/noctua/values.yaml)

```yaml
otlpGateway:
  endpoint: http://alloy-kai-alloy-node.alloy.svc.cluster.local:4318
```

**Datei:** [`apps/otel-operator/noctua/templates/instrumentation-java.yaml`](../../../apps/otel-operator/noctua/templates/instrumentation-java.yaml)

```yaml
    - name: OTEL_METRICS_EXEMPLAR_FILTER
      value: "trace_based"
  exporter:
    endpoint: {{ .Values.otlpGateway.endpoint | quote }}
```

**Alloy (bereits aktiv):** `apps/alloy/noctua-kai/values.yaml` → `applicationObservability.enabled: true` — OTLP `:4317`/`:4318` auf `alloy-node`, Weiterleitung Metrics→Mimir, Logs→Loki, Traces→Tempo. Exemplars werden im OTLP-Metrics-Pfad durchgereicht; **kein** extra Alloy-Block nötig.

**Nach Deploy:** `kubectl rollout restart deployment/spring-petclinic -n spring-petclinic`

**Exemplar-Check:**

```bash
curl -sG -H "X-Scope-OrgID: 1" \
  "http://mimir-gateway.mimir.svc.cluster.local/prometheus/api/v1/query_exemplars" \
  --data-urlencode 'query=http_server_request_duration_bucket{job=~"spring-petclinic.*"}' \
  --data-urlencode "start=$(($(date +%s)-900))" \
  --data-urlencode "end=$(date +%s)"
```

---

## 2. OTel Collector: Logs-Pipeline → Loki (optional/Labor)

**Datei:** [`apps/otel-operator/noctua/templates/open-telemetry-collector.yaml`](../../../apps/otel-operator/noctua/templates/open-telemetry-collector.yaml)

Exporter und Pipeline ergänzen:

```yaml
    exporters:
      otlphttp:
        endpoint: http://mimir-distributor.mimir.svc.cluster.local:8080/otlp
        headers:
          X-Scope-OrgID: "1"
        tls:
          insecure: true
      otlphttp/loki:
        endpoint: http://loki-gateway.loki.svc.cluster.local/otlp
        tls:
          insecure: true
      otlp/tempo:
        endpoint: tempo.tempo.svc.cluster.local:4317
        tls:
          insecure: true
    service:
      pipelines:
        metrics:
          receivers: [otlp]
          exporters: [otlphttp]
        logs:
          receivers: [otlp]
          exporters: [otlphttp/loki]
        traces:
          receivers: [otlp]
          exporters: [otlp/tempo]
```

OTLP-Logs enthalten `trace_id`/`span_id` nativ → Loki derivedFields + Tempo tracesToLogs funktionieren.

---

## 3. Spring Petclinic: Resource-Attribute

**Datei:** [`apps/spring-petclinic/noctua/templates/deployment.yaml`](../../../apps/spring-petclinic/noctua/templates/deployment.yaml)

Pod-Template-Annotations ergänzen:

```yaml
        resource.opentelemetry.io/service.name: "spring-petclinic"
        resource.opentelemetry.io/service.namespace: "spring-petclinic"
        resource.opentelemetry.io/service.version: "{{ .Values.image.tag }}"
        resource.opentelemetry.io/deployment.environment.name: "noctua"
```

Erwartete Mimir-Labels nach Alloy/Collector: `job=spring-petclinic`, `namespace=spring-petclinic`, `pod=…`, `cluster=prod-bwcloud`.

---

## 4. Tempo Metrics Generator → Mimir (Service Map)

**Datei:** [`apps/tempo/noctua/values.yaml`](../../../apps/tempo/noctua/values.yaml)

Unter `tempo:` (monolithischer Chart 1.10.1):

```yaml
    metricsGenerator:
      enabled: true
      remoteWriteUrl: "http://mimir-distributor.mimir.svc.cluster.local:8080/api/v1/push"
    overrides:
      defaults:
        metrics_generator:
          processors:
            - service-graphs
            - span-metrics
            - local-blocks
```

Erzeugt u. a. `traces_spanmetrics_*` und `traces_service_graph_*` in Mimir (siehe `.gemini/skills/tempo`).

**Optional:** Remote-Write-Header `X-Scope-OrgID: "1"` – bei Bedarf über `metricsGenerator.storage.remote_write` mit headers (neuere Chart-Version).

---

## 5. Grafana Datasources: tracesToMetrics

**Datei:** [`apps/grafana/base/values.yaml`](../../../apps/grafana/base/values.yaml)

Tempo-Block ergänzen:

```yaml
            tracesToMetrics:
              datasourceUid: mimir
            tracesToLogsV2:
              tags:
                - { key: 'service.name', value: 'service' }
                - { key: 'service.name', value: 'service_name' }
```

---

## 6. Spring-Petclinic Korrelations-Dashboard

**Neue Datei:** `apps/grafana/noctua/files/spring-petclinic/dashboards/correlation.json`

**Ordner:** wird automatisch als GrafanaFolder `Spring-Petclinic` provisioniert (Operator-Template).

### Variablen (nach `.gemini/skills/dashboarding`)

| Variable | Query |
| :--- | :--- |
| `datasource` | Prometheus/Mimir datasource |
| `loki_datasource` | Loki datasource |
| `cluster` | `label_values(kube_pod_info{namespace="petclinic"}, cluster)` |
| `namespace` | `label_values(kube_pod_info{cluster=~"$cluster", namespace="petclinic"}, namespace)` |
| `pod` | `label_values(kube_pod_info{cluster=~"$cluster", namespace=~"$namespace", pod=~"spring-petclinic.*"}, pod)` |

### Panels

| Panel | Typ | Query / Inhalt |
| :--- | :--- | :--- |
| Request Rate | timeseries | `sum(rate(http_server_request_duration_count{job=~"spring-petclinic.*", instance=~".*$pod.*"}[$__rate_interval]))` |
| Error Rate | timeseries | `sum(rate(http_server_request_duration_count{job=~"spring-petclinic.*", instance=~".*$pod.*", http_response_status_code=~"5.."}[$__rate_interval]))` |
| Latency p95 | timeseries | `histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_bucket{job=~"spring-petclinic.*", instance=~".*$pod.*"}[$__rate_interval])))` (Einheit **s**) |
| JVM Heap | timeseries | `sum by (jvm_memory_type, jvm_memory_pool_name) (jvm_memory_used{job=~"spring-petclinic.*", instance=~".*$pod.*"})` |
| Pod CPU | timeseries | `node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate5m{namespace=~"$namespace", pod=~"$pod"}` |
| Error Logs | logs | `{service_name="spring-petclinic"} \|= "ERROR"` oder `{job="spring-petclinic"} \|= "ERROR"` |
| Trace Search | text/link | Link zu Explore Tempo: `{ resource.service.name = "spring-petclinic" }` |

### Dashboard-Links

- **Kubernetes Pod:** `/d/6581e46e4e5c7ba40a07646395ef7b23?var-cluster=$cluster&var-namespace=$namespace&var-pod=$pod`
- **Tempo Explore:** `/explore?left={"datasource":"tempo","queries":[{"queryType":"traceql","query":"{ resource.service.name = \"spring-petclinic\" }"}]}`

`uid`: `spring-petclinic-correlation`, `tags`: `["spring-petclinic", "lgtm", "correlation"]`, `schemaVersion`: 41.

---

## 7. README

**Datei:** [`README.md`](../../../README.md)

Unter „Documentation & Concepts“:

```markdown
- **[LGTM Datenkorrelation (Grundlagen)](docs/ObservabilitySolutions/General/LGTM-Korrelation.md)**: Metrics → Traces → Logs, Schlüssel-Labels, Grafana-Navigation am Spring-Petclinic-Beispiel.
```

Unter „Observability Stack“ kurzer Absatz:

```markdown
- **Korrelation:** Mimir-Exemplars → Tempo, Tempo → Loki (trace_id), Loki derivedFields → Tempo. Beispiel-App: Spring Petclinic. Details: [General/LGTM-Korrelation.md](docs/ObservabilitySolutions/General/LGTM-Korrelation.md).
```

---

## 8. Validierung (nach Deploy)

| Schritt | Erwartung |
| :--- | :--- |
| `kubectl get instrumentation java-instrumentation -n otel-operator -o yaml` | `exporter.endpoint` → Alloy; `OTEL_METRICS_EXEMPLAR_FILTER=trace_based` |
| Grafana → Mimir | `http_server_request_duration_*{job=~"spring-petclinic.*"}` liefert Daten |
| Mimir exemplars API | Einträge mit `trace_id` nach Traffic |
| Grafana → Loki | `{service_name="spring-petclinic"}` zeigt Logs |
| Grafana Latency-Panel | Exemplar-Marker (Diamant) → Klick öffnet Tempo |

---

## 9. Metriken-Inventar (Referenz)

Typische OTel-Java-Metriken in Mimir (Noctua-Cluster, Semantic Conventions):

- `http_server_request_duration_bucket/count/sum` (Histogram in **Sekunden**, Label `http_response_status_code`)
- `http_server_active_requests`
- `jvm_memory_used` (Labels `jvm_memory_type`, `jvm_memory_pool_name`)
- `job="spring-petclinic/spring-petclinic"` — kein `namespace`/`pod` auf App-Metriken; Pod-Filter über `instance=~".*<pod>.*"`
- `jvm_gc_duration_seconds_*`
- `process_runtime_jvm_*`

Trace-Attribute in Tempo: `resource.service.name`, `http.response.status_code`, `url.path`.

Log-Labels in Loki (OTLP): `trace_id`, `span_id`, `service_name`, `k8s_namespace_name`, `k8s_pod_name`.
