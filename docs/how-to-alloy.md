# Alloy Observability Pipeline – Architektur und Betriebsleitfaden

## 1. Zweck und Zielbild
Dieses Dokument beschreibt die Architekturentscheidungen für die Kubernetes-Metrikpipeline mit Alloy und Mimir.

Ziele:
- nachvollziehbare technische Entscheidungen für Team und Betrieb
- einheitliche Label-Strategie für stabile Dashboards und Alerts
- kontrollierte Cardinality und planbarer Ressourcenverbrauch
- vendor-neutrale Entwicklung mit OTLP als Egress-Standard

## 2. Scope

In Scope:
- Metrik-Erfassung aus Kubernetes über Alloy
- Export nach Mimir über OTLP/HTTP
- Label-Governance und Cardinality-Kontrolle

Out of Scope:
- zentrale Gateway-Topologie (als nächster Ausbauschritt vorgesehen)
- Traces/Logs-Ingestion-Details

## 3. Metrik-Domänen (aktuell)

Aktive Domänen:
- kube-state-metrics
- node-exporter
- kubelet
- cadvisor

## 3.1 ServiceMonitor-Anforderungen

Für die Zielarchitektur wird vorausgesetzt, dass folgende Komponenten über `ServiceMonitor`-Ressourcen verfügbar sind:
- kube-state-metrics
- node-exporter
- kubelet
- cadvisor
- kube-apiserver
- CoreDNS

Regel zur Vermeidung von Doppel-Ingestion:
- pro Komponente nur **einen** aktiven Scrape-Pfad betreiben
- entweder direkter Flow-Scrape in Alloy **oder** Scrape über ServiceMonitor-basierte Discovery

## 3.2 ServiceMonitor-relevante Felder

Für konsistente Labelbildung und Routing sind folgende Felder in den ServiceMonitor-Manifesten relevant:

- `spec.selector` / `spec.namespaceSelector`
	- steuern, welche Services und Namespaces tatsächlich gescraped werden

- `spec.endpoints[]`
	- `port`/`targetPort`, `path`, `scheme`, `interval`, `scrapeTimeout`, `tlsConfig`, `bearerTokenFile`
	- definiert Scrape-Protokoll und Transportparameter

- `spec.jobLabel`
	- legt fest, aus welchem Service-Label der `job`-Wert erzeugt wird
	- wichtig für stabile Filterregeln in zentralem Relabeling

- `spec.endpoints[].relabelings`
	- target-seitiges Relabeling (z. B. `job`, `instance`, `cluster` setzen/überschreiben)

- `spec.endpoints[].metricRelabelings`
	- sample-seitiges Relabeling (z. B. volatile Labels droppen, Metric-Familien filtern)

## 4. Architekturentscheidung (aktuell)

- Alloy läuft als DaemonSet.
- Kubernetes-Infrastrukturmetriken werden ServiceMonitor-first erfasst.
- Instrumentierte Anwendungen übertragen Metriken per OTLP/gRPC an Alloy.
- Export erfolgt per OTLP/HTTP nach Mimir.

## 5. Datenfluss

1. ServiceMonitor-Discovery und Scraping (`prometheus.operator.servicemonitors`)
2. Zentrale Metric-Governance (`prometheus.relabel.metrics_normalize_filter`)
3. Bridge in OTel-Pipeline (`otelcol.receiver.prometheus.all_metrics`)
4. Enrichment (`otelcol.processor.k8sattributes` + `otelcol.processor.resourcedetection`)
5. Batch Processing (`otelcol.processor.batch`)
6. Export (`otelcol.exporter.otlphttp`)

## 6. Label-Governance (verbindlich)

Primärmodell:
- `k8s_cluster_name`, `k8s_namespace_name`, `k8s_pod_name`, `k8s_node_name`

Sekundärmodell:
- `cluster`, `namespace`, `pod`, `node`, `job`, `instance`

### 6.1 Relabel-Strategie (Hybridmodell)

Die Relabel-Strategie ist zweistufig aufgebaut:

1. Frühe, komponentenspezifische Relabeling-Schritte
- je Komponente im jeweiligen `ServiceMonitor` (`relabelings` / `metricRelabelings`)
- Ziel: korrekte Targets und technische Pflichtlabels (`job`, `instance`, `cluster`, `node`)

2. Zentrale, einheitliche Label-Governance
- einmalig in `prometheus.relabel.metrics_normalize_filter`
- Ziel: konsistenter Label-Vertrag über alle Prometheus-Scrapes
- umfasst volatile Label-Drops, Aufbau der `k8s_*`-Spiegellabel und ein gemeinsames Label-Allowlist-Verhalten

Reihenfolgehinweis:
- `labelkeep` wirkt auf Prometheus-Labels **vor** OTel-Enrichment.
- `otelcol.processor.k8sattributes` und `otelcol.processor.resourcedetection` ergänzen danach Resource-Attribute.
- Dadurch gilt: query-relevante `k8s_*`-Spiegellabel werden im zentralen Relabeling erzeugt; OTel-Prozessoren liefern zusätzliche semantische Resource-Kontexte.

Begründung:
- rein frühes Relabeling führt bei vielen Komponenten zu Regel-Drift
- rein spätes Relabeling verliert komponentenspezifische Target-Logik
- das Hybridmodell verbindet Wartbarkeit mit technischer Präzision

## 7. Golden Query Contract

Golden Queries basieren auf:
- Kubernetes-Mixin
- produktiv verwendeten Dashboard-Queries
- Alert-Regeln

### 7.1 kube-state-metrics

| # | Query |
|---|---|
| 1 | `sum by (cluster, namespace) (kube_pod_status_phase{phase="Running"})` |
| 2 | `sum by (cluster, namespace, deployment) (kube_deployment_status_replicas_available)` |
| 3 | `sum by (cluster, namespace, pod) (kube_pod_container_status_restarts_total)` |
| 4 | `sum by (cluster, namespace) (kube_namespace_status_phase{phase="Active"})` |
| 5 | `sum by (cluster, node) (kube_node_status_condition{condition="Ready",status="true"})` |

### 7.2 node-exporter

| # | Query |
|---|---|
| 1 | `avg by (cluster, node) (rate(node_cpu_seconds_total{mode!="idle"}[5m]))` |
| 2 | `avg by (cluster, node) (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)` |
| 3 | `sum by (cluster, node, device) (rate(node_disk_read_bytes_total[5m]))` |
| 4 | `sum by (cluster, node, device) (rate(node_network_receive_bytes_total[5m]))` |
| 5 | `avg by (cluster, node, mountpoint) (node_filesystem_avail_bytes / node_filesystem_size_bytes)` |

### 7.3 kubelet

| # | Query |
|---|---|
| 1 | `sum by (cluster, node) (rate(kubelet_runtime_operations_total[5m]))` |
| 2 | `histogram_quantile(0.99, sum by (le, cluster, node) (rate(kubelet_runtime_operations_duration_seconds_bucket[5m])))` |
| 3 | `sum by (cluster, node) (kubelet_running_pods)` |
| 4 | `sum by (cluster, node) (rate(kubelet_pod_worker_duration_seconds_count[5m]))` |
| 5 | `sum by (cluster, node) (rate(kubelet_pleg_relist_duration_seconds_count[5m]))` |

### 7.4 cadvisor

| # | Query |
|---|---|
| 1 | `sum by (cluster, namespace, pod, container) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))` |
| 2 | `sum by (cluster, namespace, pod, container) (container_memory_working_set_bytes{container!=""})` |
| 3 | `sum by (cluster, namespace, pod, container) (rate(container_network_receive_bytes_total{container!=""}[5m]))` |
| 4 | `sum by (cluster, namespace, pod, container) (rate(container_fs_reads_bytes_total{container!=""}[5m]))` |
| 5 | `sum by (cluster, namespace, pod, container) (rate(container_fs_writes_bytes_total{container!=""}[5m]))` |

### 7.5 Mindestabdeckung pro Domäne

| Domäne | Mindestmetriken |
|---|---|
| kube-state-metrics | `kube_pod_status_phase`, `kube_deployment_status_replicas_available`, `kube_pod_container_status_restarts_total`, `kube_namespace_status_phase`, `kube_node_status_condition` |
| node-exporter | `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes`, `node_disk_read_bytes_total`, `node_network_receive_bytes_total` |
| kubelet | `kubelet_runtime_operations_total`, `kubelet_runtime_operations_duration_seconds_bucket`, `kubelet_running_pods`, `kubelet_pod_worker_duration_seconds_count`, `kubelet_pleg_relist_duration_seconds_count` |
| cadvisor | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`, `container_network_receive_bytes_total`, `container_fs_reads_bytes_total`, `container_fs_writes_bytes_total` |

## 8. Cardinality-Budget und Reviews

- Budget pro Job und Namespace
- monatliches Review von Series-Wachstum und Labelnutzung

## 9. Nächste Architektur-Entscheidung

Einführung eines zentralen OTel-Gateways.
Rahmenbedingungen: [apps/alloy/base/values.yaml](apps/alloy/base/values.yaml)

## 10. Empfehlung für Multi-Cluster-Betrieb

Für Umgebungen mit vielen Clustern und unterschiedlichen Rollen (Customer, Observability, Management) wird ein dreistufiges Konfigurationsmodell empfohlen:

1. Baseline (global)
- identische Standard-Pipeline für alle Cluster
- einheitliche Label-Normalisierung und Golden Queries
- zentrale Metric-Governance über `metrics_normalize_filter`

2. Clusterprofil (rollenbasiert)
- eigenes Profil je Cluster-Typ, z. B. `customer`, `observability`, `management`
- profilbezogene Filter und Limits, z. B. cAdvisor Namespace-Allowlist im Observability-Cluster

3. Gezielte Ausnahmen (eng begrenzt)
- namespace- oder tenant-spezifische Relabel-Regeln
- optional zusätzlicher Exportpfad für Migrationsphasen (Dual-Export)
- Änderungen nur per GitOps Pull Request und mit Ablaufdatum/Review-Termin

Hinweis zur Übergabe an externe Plattformen:
- Das Konzept mit `ServiceMonitor`/`PodMonitor` kann unverändert bestehen bleiben.
- Die vorgeschlagene Verbesserung liegt primär in der einheitlichen Relabel- und Label-Governance-Schicht.

Umsetzungsprinzip:
- 90% der Verarbeitung in Baseline + Profil halten
- Ausnahmen minimal und zeitlich begrenzt halten
- jede Ausnahme mit Golden Query und Cardinality-Check validieren

## 11. Kompatibilität mit Grafana Mimir Dashboards und Alerts

Gemäß den Mimir-Anforderungen für Dashboards/Alerts müssen folgende Labels konsistent verfügbar sein:
- `cluster`
- `namespace`
- `job`
- `pod`
- `instance`

Zusätzliche Anforderungen:
- Scrape-Intervall für Mimir-Monitoring-Metriken: `15s` oder kürzer
- Ressourcen-Dashboards setzen Metriken aus `kubelet`, `cadvisor`, `node-exporter` und `kube-state-metrics` voraus
- `cluster` muss über die relevanten Kubernetes-Quellen konsistent denselben Wert tragen
- `instance` muss für `node-exporter` und `cadvisor` konsistent belegt sein

Konsequenz für diese Pipeline:
- Prometheus-kompatible Labels (`cluster`, `namespace`, `job`, `pod`, `instance`) bleiben verpflichtend
- `k8s_*`-Labels bleiben als Primärmodell für neue Artefakte zusätzlich erhalten

### 11.1 Mimir Attribut-Promotion (zukünftige Option)

Grafana Mimir kann OpenTelemetry-Resource-Attribute bei Ingestion zu Prometheus-Labels promoten.

Status in dieser Lösung:
- wird aktuell **nicht** verwendet
- bleibt als zukünftige Option dokumentiert
- Grund: die Funktion ist in Mimir als experimentell eingeordnet und wird daher derzeit nicht als Standardpfad genutzt

Aktueller Kompromiss:
- query-kritische `k8s_*`-Spiegellabel bleiben auf der Serie
- OTel-Resource-Attribute aus `k8sattributes` und `resourcedetection` werden weiterhin angereichert
- zusätzliche Attribute sind über `target_info` verfügbar

### 11.2 Querying von Resource-Attributen ohne Mirroring

Wenn ein Attribut nur als Resource-Attribut vorliegt (z. B. `cloud_account_id`), kann es über `target_info` per Join in PromQL genutzt werden.

Beispielmuster:

`sum by (cluster, namespace, pod) (rate(container_cpu_usage_seconds_total[5m]) * on (job, instance) group_left(cloud_account_id) target_info{cloud_account_id="<PROJECT_OR_ACCOUNT_ID>"})`

Hinweise:
- Join-Schlüssel sind typischerweise `job` und `instance` (ggf. zusätzlich `cluster` je nach Labelset).
- Das Muster funktioniert ohne direktes Mirroring von `cloud_account_id` auf jede Zeitserie.

## 12. Review-Queries für Cardinality

- `topk(20, count by (__name__)({__name__!=""}))`
- `topk(20, count by (__name__, job)({__name__!=""}))`
- `topk(20, count by (cluster, namespace, pod)({pod!=""}))`
- `topk(20, count by (cluster, namespace)({namespace!=""}))`

## 13. Quellenbasis

- https://github.com/kubernetes-monitoring/kubernetes-mixin
- https://github.com/kubernetes-monitoring/kubernetes-mixin/blob/main/dashboards/dashboards.libsonnet
- https://github.com/kubernetes-monitoring/kubernetes-mixin/blob/main/dashboards/resources/queries/cluster.libsonnet
- https://github.com/kubernetes-monitoring/kubernetes-mixin/blob/main/dashboards/resources/queries/namespace.libsonnet
- https://github.com/kubernetes-monitoring/kubernetes-mixin/blob/main/dashboards/resources/queries/pod.libsonnet
- https://github.com/kubernetes-monitoring/kubernetes-mixin/blob/main/dashboards/kubelet.libsonnet
- https://github.com/kubernetes-monitoring/kubernetes-mixin/blob/main/rules/apps.libsonnet
- https://github.com/kubernetes-monitoring/kubernetes-mixin/blob/main/rules/node.libsonnet
- https://github.com/grafana/mimir/blob/main/docs/sources/mimir/configure/configure-otel-collector.md
- https://github.com/grafana/mimir/blob/main/docs/sources/mimir/manage/monitor-grafana-mimir/requirements.md

## 14. Migrationsstrategie (Backend-Wechsel)

1. Dual-Write für neue Daten aktivieren.
2. Bestehendes Backend temporär als Read-only-Historie betreiben.
3. Dashboards und Alerts schrittweise auf das neue Backend umstellen.

Hinweis:
- Historische TSDB-Daten sind meist nicht 1:1 migrierbar.
- Entscheidend ist die Stabilität von Query- und Label-Verträgen.

## 15. Cross-Signal-Korrelation

Cross-Signal-Korrelation (Metriken, Logs, Traces) ist ein strategischer Use-Case.
Für neue Artefakte bleibt `k8s_*` primär, während Prometheus-Labels für Kompatibilität erhalten bleiben.
