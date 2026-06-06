# Analyse fehlender Dashboard-Panels (No Data) in Alloy, Kubernetes, Mimir und Tempo

Dieses Dokument listet alle Panels der Grafana-Dashboards für **Grafana Alloy**, **Kubernetes**, **Grafana Mimir** und **Grafana Tempo** auf, die im Standardbetrieb keine Daten anzeigen (`No Data`), und klassifiziert, ob dies korrekt (**OK**) oder ein Fehler (**ERROR**) ist.

> [!NOTE]
> **Update vom 06. Juni 2026:**
> Alle zuvor als **ERROR** markierten fehlenden Panels (z. B. CPU-Nutzung in Kubernetes-Dashboards und API-Server-Verfügbarkeit) wurden durch die Bereitstellung von benutzerdefinierten Aggregationsregeln (Recording Rules) in [recording-rules.yaml](file:///Users/saad.masood/Documents/Git/bwcloud-gitops/apps/mimir/noctua/files/kubernetes/custom/recording-rules.yaml) erfolgreich behoben. Alle Dashboards wurden in die jeweiligen `accepted/`-Ordner verschoben.

---

# Teil 1: Grafana Alloy Dashboards

In unserem **OTLP-first** Observability-Stack ist dieses Verhalten für fast alle Panels völlig **korrekt (OK)**, da wir moderne OpenTelemetry-Pipelines nutzen und auf veraltete (Legacy-)Komponenten verzichten.

## 1. Alloy / Cluster Node (`alloy-cluster-node.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Packet write success rate** | **OK** | Fragt Paketverluste im Gossip-Clustering ab (`cluster_transport_rx_packets_failed_total`). Da im gesunden Clusterbetrieb keine Pakete verloren gehen, wird diese Metrik von Mimir nicht initialisiert. |
| **Stream write success rate** | **OK** | Fragt Fehler bei Streaming-Verbindungen ab (`cluster_transport_stream_rx_packets_failed_total`). Da alle Streams fehlerfrei laufen, existiert die Metrik nicht. |

## 2. Alloy / Cluster Overview (`alloy-cluster-overview.json`)

*Dieses Dashboard ist vollständig funktionsfähig. Alle Panels empfangen Daten.*

## 3. Alloy / Controller (`alloy-controller.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Slow components evaluation times** | **OK** | Zählt Komponentenevaluierungen, die ein definiertes Limit (>100ms) überschreiten. Da die Evaluierungen extrem performant laufen und keine Verzögerungen auftreten, bleibt dieser Zähler uninitialisiert. |

## 4. Alloy / Logs Overview (`alloy-logs.json`)

*Dieses Dashboard fragt LogQL-Metriken ab. Da Alloy-Logs erfolgreich an Loki gesendet werden, sind alle Panels aktiv.*

## 5. Alloy / Loki Components (`alloy-loki.json`)

> [!NOTE]
> Dieses Dashboard ist **vollständig leer**. Dies ist in unserem Setup **korrekt (OK)**. Wir setzen eine moderne OpenTelemetry-Pipeline (`otelcol.receiver.filelog`) ein, um Logs zu lesen, und verzichten auf die veralteten Loki-spezifischen Komponenten (`loki.source.file`, `loki.write`, etc.).

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Active files count $cluster** | **OK** | `loki.source.file` wird nicht verwendet. Logs werden stattdessen über den OTel-basierten `otelcol.receiver.filelog` gelesen. |
| **Lines read in $cluster** | **OK** | Die Legacy-Komponente `loki.source.file` ist nicht konfiguriert. |
| **Journal lines read in $cluster** | **OK** | Die Legacy-Komponente `loki.source.journal` ist in Alloy inaktiv. |
| **Write requests success rate in $cluster** | **OK** | Logs werden über OTLP HTTP (`otelcol.exporter.otlphttp`) statt über die Legacy-Schreibkomponente `loki.write` exportiert. |
| **Write latency in $cluster** (99th, 95th, 50th) | **OK** | Da `loki.write` inaktiv ist, werden keine Latenzmetriken (`loki_write_request_duration_seconds_bucket`) erfasst. |
| **Bytes sent in $cluster** | **OK** | Keine Datenübertragung via Legacy-Loki-Schreibkomponenten. |
| **Bytes dropped in $cluster** | **OK** | Es sind keine Legacy-Log-Exporter aktiv, die Logs verwerfen könnten. |
| **Write request size distribution in $cluster** | **OK** | Keine Metriken von `loki.write` vorhanden. |
| **Entry propagation latency in $cluster** (99th, 50th) | **OK** | Keine Legacy-Verbreitungsmetriken vorhanden. |

## 6. Alloy / OpenTelemetry (`alloy-opentelemetry.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Accepted metric points** | **OK** | Interne Alloy-Engine-Metriken. **Anwendungs-OTLP** geht an `alloy-kai-alloy-node` (`applicationObservability`, Ports 4317/4318) → Mimir/Loki/Tempo. |
| **Refused metric points** | **OK** | Da keine Metriken über die OTel-Engine von Alloy empfangen werden, werden auch keine abgewiesen. |
| **Accepted spans** | **OK** | Derzeit werden keine Anwendungs-Traces (Spans) über Alloy geleitet (Tempo-Integration läuft direkt oder über den OTel-Operator). |
| **Refused spans** | **OK** | Da keine Traces verarbeitet werden, gibt es keine verweigerten Spans. |
| **RPC server duration** | **OK** | Es wird kein eingehender OTel-gRPC-Verkehr direkt an Alloy gesendet. |
| **HTTP server duration** | **OK** | Es wird kein eingehender OTel-HTTP-Verkehr direkt an Alloy gesendet. |
| **Failed metric points** | **OK** | Da alle ausgehenden Metriken erfolgreich an Mimir gesendet wurden, ist der Fehlerzähler leer. |
| **Failed logs** | **OK** | Alle Logs wurden erfolgreich exportiert, daher keine Fehler verzeichnet. |
| **Exported spans** | **OK** | Traces werden von Alloy nicht verarbeitet oder exportiert. |
| **Failed spans** | **OK** | Keine Traces verarbeitet, somit keine Exportfehler. |
| **RPC client duration** | **OK** | Wir exportieren Telemetriedaten via HTTP (OTLP/HTTP) an Mimir/Loki und nutzen kein gRPC für den Export. |
| **HTTP client duration** | **OK** | Der HTTP-Client der OTel-Engine in Alloy registriert unter dieser spezifischen Abfrage keine Dauer-Metriken in dieser Version. |

## 7. Alloy / OTel Engine Overview (`alloy-otel-engine-overview.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Pods count** | **OK** | Fragt `otelcol_process_uptime_seconds_total` ab. Alloy stellt diese Metrik nicht bereit, da er zur Ressourcenüberwachung seine eigene Engine (`alloy_resources_process_*`) nutzt. |
| **Recently started by ${groupby}** | **OK** | OTel-Prozessmetriken fehlen in Alloy (siehe oben). |
| **Receivers SR** (Spans, Metric points) | **OK** | Keine Traces/Metriken werden per OTLP in der Alloy-OTel-Engine verarbeitet. |
| **Exporters SR** (Spans) | **OK** | Keine Traces werden über Alloy exportiert. |
| **Receiver: Total accepted & refused** (Spans, Metrics) | **OK** | Kein OTLP-Eingang für Spans oder Metriken. |
| **Receiver: Accepted by ${groupby}** (Spans, Metrics) | **OK** | Kein OTLP-Eingang für Spans oder Metriken. |
| **Receiver: Refused by ${groupby}** (Spans, Metrics) | **OK** | Kein OTLP-Eingang für Spans oder Metriken. |
| **Exporter: Total sent & failed** (Spans, failed metrics, failed logs, failed spans) | **OK** | Keine Traces vorhanden und fehlerfreier Export von Logs und Metriken. |
| **Exporter: Sent by ${groupby}** (Spans) | **OK** | Keine Traces verarbeitet. |
| **Exporter: Failed by ${groupby}** (Spans, failed metrics, failed logs, failed spans) | **OK** | Keine Traces verarbeitet und fehlerfreier Export von Logs/Metriken. |
| **Processor refused by ${groupby}** | **OK** | Keine Spans oder Metriken wurden von den Processoren in Alloy abgewiesen. |
| **CPU usage** (beide Panels) | **OK** | Fragt `otelcol_process_cpu_seconds_total` ab. Diese Metrik existiert nicht; die CPU-Auslastung wird stattdessen auf dem Dashboard **Alloy / Resources** via `alloy_resources_process_cpu_seconds_total` korrekt angezeigt. |
| **Memory RSS** (beide Panels) | **OK** | Fragt `otelcol_process_memory_rss_bytes` ab. Die Speichernutzung wird stattdessen über das Dashboard **Alloy / Resources** via `alloy_resources_process_resident_memory_bytes` überwacht. |
| **Go allocation rate** (beide Panels) | **OK** | Diese OTel-Collector-spezifische Metrik existiert in Alloy nicht. |
| **Unique hosts tracked** | **OK** | Fragt `otelcol_grafanacloud_host_count_ratio` ab, was nur bei einer Integration mit der Grafana Cloud erzeugt wird. |
| **Datapoints sent rate** | **OK** | Fragt `otelcol_grafanacloud_datapoint_count_total` ab (nur Grafana Cloud). |

## 8. Alloy / Prometheus Components (`alloy-prometheus-remote-write.json`)

> [!NOTE]
> Dieses Dashboard ist ebenfalls **vollständig leer**. Dies ist im OTLP-first Stack **korrekt (OK)**. Wir senden Metriken über das standardisierte OTLP-HTTP-Protokoll an Mimir (`otelcol.exporter.otlphttp`), wodurch keine Legacy-Prometheus-Schreibkomponenten (`prometheus.remote_write`) zum Einsatz kommen.

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Remote write success rate in $cluster** | **OK** | Wir nutzen keine `prometheus.remote_write`-Komponenten. |
| **Write latency in $cluster** (99th, 50th, average) | **OK** | Die entsprechenden Metriken (`prometheus_remote_storage_sent_batch_duration_seconds_bucket`) sind inaktiv. |
| **WAL delay** | **OK** | Da kein Prometheus-WAL für den Remote-Write genutzt wird, gibt es hierzu keine Metriken. |
| **Data write throughput** | **OK** | Keine Metriken zur Remote-Write-Schreibbandbreite vorhanden. |
| **Shards** (current, min, max) | **OK** | Remote-Write-Sharding ist inaktiv. |
| **Sent samples / second** | **OK** | Keine Metriken zu gesendeten remote-write-Samples. |
| **Failed samples / second** | **OK** | Keine Fehler bei remote-write vorhanden. |
| **Retried samples / second** | **OK** | Keine Retries bei remote-write vorhanden. |
| **Active series (total)** | **OK** | WAL-Speicher-Metriken für remote-write sind inaktiv. |
| **Active series (by instance/component)** | **OK** | WAL-Speicher-Metriken für remote-write sind inaktiv. |
| **Active series (by component)** | **OK** | WAL-Speicher-Metriken für remote-write sind inaktiv. |

## 9. Alloy / Resources (`alloy-resources.json`)

*Dieses Dashboard ist vollständig funktionsfähig. Alle CPU-, Speicher-, Netzwerk- und Laufzeitmetriken von Alloy werden erfolgreich angezeigt.*

---

# Teil 2: Kubernetes Dashboards

## 1. Kubernetes / API server (`k8s-system-api-server.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Availability / SLI / ErrorBudget** | **OK (RESOLVED)** | Die benötigte Aggregationsmetrik `apiserver_request:availability30d` wurde als benutzerdefinierte Recording Rule per Mimir-Ruler bereitgestellt. Die Panels erhalten nun Daten. |

## 2. Kubernetes / Compute Resources / Cluster (`k8s-resources-cluster.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **CPU Usage** | **OK (RESOLVED)** | Die Recording Rule `node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate5m` wurde per Mimir-Ruler definiert. CPU-Daten werden nun visualisiert. |

## 3. Kubernetes / Compute Resources / Namespace (Pods) (`k8s-resources-namespace.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **CPU Utilisation (limits & requests)** | **OK (RESOLVED)** | Die Recording Rule `node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate5m` wurde bereitgestellt. |

## 4. Kubernetes / Compute Resources / Node & Pod

*Diese Dashboards nutzen direkte Metriken und funktionieren einwandfrei.*

## 5. Kubernetes / Compute Resources / Workload (`k8s-resources-workload.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **CPU Usage** | **OK (RESOLVED)** | Die benötigten Recording Rules (`node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate5m` und `namespace_workload_pod:kube_pod_owner:relabel`) wurden deployed. |

## 6. Kubernetes / Controller Manager (`k8s-system-controller-manager.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Alle Panels** | **OK** | Der Controller-Manager läuft in unserer Umgebung (K3s/Managed) intern bzw. wird nicht per Prometheus/Alloy gescrapt. Dies ist das Standardverhalten bei integrierten/managed Control-Planes. |

## 7. Kubernetes / Kubelet (`k8s-system-kubelet.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Operation Duration 99th quantile** | **OK** | Nutzt `kubelet_runtime_operations_duration_seconds_bucket`. Diese detaillierte Metrik wird durch die Whitelist-Relabeling-Regeln in Alloy (`apps/alloy/noctua-kai/render.yaml`) verworfen, um Mimir-Speicherplatz zu sparen. |
| **Config Error Count** | **OK** | Nutzt `kubelet_node_config_error`. Bleibt leer, da bisher 0 Konfigurationsfehler auftraten. |
| **Storage Operation Duration 99th quantile** | **OK** | Die Metrik `storage_operation_duration_seconds_bucket` ist nicht im Metriken-Whitelist von Alloy enthalten und wird verworfen. |
| **Storage Operation Error Rate** | **OK** | Zähler für Speicherfehler steht bei 0, daher keine Daten. |
| **Request duration 99th quantile** | **OK** | HTTP-Dauer-Metriken der Kubelet-API sind nicht whitelisted. |

## 8. Kubernetes / Proxy (`k8s-system-proxy.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Alle Panels** | **OK** | Die Metrik-Endpoints von Kube-Proxy sind in unserer K3s-Umgebung nicht für Scraping konfiguriert. |

## 9. Kubernetes / Scheduler (`k8s-system-scheduler.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Alle Panels** | **OK** | Der Scheduler läuft intern in der K3s-Runtime und wird nicht per Prometheus-Scrape erfasst. |

---

# Teil 3: Grafana Mimir Dashboards

## 1. Mimir / Rollout progress (`mimir-rollout-progress.json`)

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Writes 99th latency** | **OK** | Zeigt nur während eines aktiven Mimir-Upgrades/Rollouts Daten an. Im stabilen Normalbetrieb leer. |
| **Reads 99th latency** | **OK** | Zeigt nur bei Upgrades Latenz-Veränderungen an. |
| **Unhealthy pods** | **OK** | Steht im gesunden Zustand auf 0. |
| **Reads/Writes - 4xx / 5xx** | **OK** | Zeigt keine Daten, da aktuell keine Lese- oder Schreibfehler (HTTP 4xx/5xx) auftreten. |
| **Latency vs 24h ago** | **OK** | Dient dem Vergleich während Rollouts, im stabilen Betrieb inaktiv. |

## 2. Alle anderen 26 Mimir Dashboards

*Alle Panels dieser Dashboards erhalten erfolgreich und lückenlos Daten. Die Mimir-eigene Telemetrie ist vollständig intakt.*

---

# Teil 4: Grafana Tempo Dashboards

| Panel | Status | Erklärung |
| :--- | :--- | :--- |
| **Keine Dashboards** | **OK** | Derzeit sind keine Tempo-spezifischen Dashboards importiert. Traces werden direkt über die *Explore*-Ansicht visualisiert, was für unser Setup korrekt ist. |
