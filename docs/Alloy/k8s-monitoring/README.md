# Altes Konzept: `k8s-monitoring` Chart in Noctua-Kai

Diese Doku beschreibt das bisherige `noctua-kai` Konzept auf Basis der Grafana `k8s-monitoring` Helm Chart. Sie dient als Referenz fuer das alte Modell und als Vergleichsbasis fuer das neue modulare Noctua-Deployment.

Der alte Ansatz liegt im Repo unter:

```text
apps/alloy/noctua-kai/
```

## Grundidee

Die `k8s-monitoring` Chart generiert Alloy-Konfiguration fuer Kubernetes-Monitoring. Sie bringt viele Features bereits mit:

- Kubernetes Cluster Metrics.
- Node Exporter Deployment und Scraping.
- kube-state-metrics Deployment und Scraping.
- Kubelet und cAdvisor Scrapes.
- Annotation Autodiscovery.
- Pod Logs.
- Application Observability via OTLP.
- Alloy Operator und Alloy Custom Resources.
- Destinations fuer Mimir, Loki, Tempo und weitere OTLP Backends.

Das war der Grund, warum das Chart urspruenglich attraktiv war: viel Telemetry-Feature-Set mit wenig eigener River-Konfiguration.

## Render-Modell

`noctua-kai` rendert nicht einfach eine einzelne direkte Alloy ConfigMap. Das Deployment besteht aus mehreren Ebenen:

| Ebene | Beschreibung |
| --- | --- |
| Helm Values | `apps/alloy/noctua-kai/values.yaml` steuert die Chart. |
| `k8s-monitoring` Chart | Generiert Collector-, Feature- und Destination-Konfiguration. |
| Alloy Operator | Erstellt/verwaltet Alloy CRs. |
| Alloy CRs | `noctua-kai-alloy-node` und `noctua-kai-alloy-metrics`. |
| Zusatz-ConfigMap | `templates/alloy-modules-configmap.yaml` stellt `k8s-enrich.alloy` bereit. |
| ServiceMonitor | `templates/servicemonitor.yaml` scrapt Alloy Self-Metrics. |

Gerenderte Ressourcen waren typischerweise:

- `Alloy/noctua-kai-alloy-node`
- `Alloy/noctua-kai-alloy-metrics`
- `Deployment/noctua-kai-alloy-operator`
- `Deployment/noctua-kai-kube-state-metrics`
- `DaemonSet/noctua-kai-node-exporter`
- `ConfigMap/alloy-modules`
- `ConfigMap/noctua-kai-alloy-node`
- `ConfigMap/noctua-kai-alloy-metrics`
- RBAC, Services und ServiceAccounts

## Telemetry-Quellen

Die Chart generierte im Kern diese Scrape-/Ingestion-Quellen:

| Quelle | Chart-Komponente |
| --- | --- |
| OTLP Application Telemetry | `applicationObservability` / `otelcol.receiver.otlp` |
| Pod Logs | `podLogsViaOpenTelemetry` / `otelcol.receiver.filelog` |
| Annotation Autodiscovery | `annotation_autodiscovery` |
| Kubelet `/metrics` | `cluster_metrics` |
| Kubelet `/metrics/resource` | `cluster_metrics` |
| cAdvisor | `cluster_metrics` |
| kube-state-metrics | `cluster_metrics` |
| node-exporter | `node_exporter` |
| kube-apiserver | `cluster_metrics` |
| kube-controller-manager | `cluster_metrics` |
| kube-scheduler | `cluster_metrics` |
| kube-proxy | `cluster_metrics` |
| kube-dns/CoreDNS | `cluster_metrics` |
| ServiceMonitors | `prometheus.operator.servicemonitors` |

Das neue Noctua-Deployment hat diese Quellen als explizite Module nachgebaut, damit die Feature-Abdeckung erhalten bleibt.

## Anpassungen im alten Konzept

Das `noctua-kai` Deployment wurde stark ueber `replaceComponent` angepasst. Beispiele:

- `otelcol.receiver.prometheus "mimir"` wurde umverdrahtet, damit ein eigener `memory_limiter` frueh im Metrics-Pfad greift.
- `otelcol.processor.k8sattributes "pod_logs"` wurde ersetzt, um Logs per `k8s.pod.uid` anzureichern.
- `otelcol.processor.filter "pod_logs"` wurde ersetzt, um OTel-injizierte Pods aus Filelog-Scraping herauszunehmen.
- `otelcol.processor.transform "pod_logs"` wurde ersetzt, um Service-Identity und Secret-Drops zu setzen.
- Zusaetzliche River-Module wurden ueber `alloy-modules` eingebunden.

Diese Anpassungen waren technisch wirksam, fuehrten aber zu einem wichtigen Wartungsproblem: Die fachliche Regel "setze identische Kubernetes-Metadaten fuer Metrics und Logs" verteilte sich auf mehrere Chart-Mechanismen.

## Warum es unuebersichtlich wurde

Die `k8s-monitoring` Chart hat viele gute Defaults, aber sie versteckt Komplexitaet. Im konkreten Noctua-Kai Setup entstanden mehrere Problemklassen.

### 1. Chart-generierte River-Dateien

Ein grosser Teil der Alloy-Konfiguration entsteht erst beim Rendern. Man liest also nicht direkt die produktive River-Konfiguration, sondern Values, Chart-Templates und Render-Ergebnis.

Das macht Reviews schwer:

- Ist eine Regel von uns?
- Ist sie Chart-Default?
- Wird sie durch `replaceComponent` ersetzt?
- Wird sie an anderer Stelle trotzdem nochmal erzeugt?

### 2. `replaceComponent` als Patch-Mechanismus

`replaceComponent` ist maechtig, aber nicht sehr lokal. Man ueberschreibt eine chart-interne Komponente, die von der Chart an anderer Stelle referenziert wird.

Das fuehrt zu Kopplung an interne Chart-Namen:

```yaml
replaceComponent:
  - type: otelcol.processor.k8sattributes
    name: pod_logs
    module: pod_logs_via_opentelemetry
```

Wenn die Chart-Struktur oder Komponentennamen sich aendern, kann eine Anpassung still brechen oder anders wirken.

### 3. Doppelte OTTL-Logik

OTTL-Regeln fuer Redaction, Service-Identity, Legacy-Labels und Kubernetes-Metadaten tauchten an mehreren Stellen auf:

- In Chart Values unter Destinations.
- In `replaceComponent` Blocks.
- In `alloy-modules-configmap.yaml`.
- Im gerenderten `alloy-node`.
- Im gerenderten `alloy-metrics`.

Die Pipeline-Kontexte muessen technisch getrennt sein, aber die fachlichen Regeln sollten nicht mehrfach manuell gepflegt werden.

### 4. Backend-spezifische Defaults

Loki, Mimir, Elastic und Tempo brauchen unterschiedliche Signal-Typen und Protokolle. Die Chart kann das abbilden, aber bei Spezialfaellen wie "Loki nur Logs" oder "Elastic nur Logs ohne Loki-Labels" musste trotzdem sehr genau nachgesteuert werden.

### 5. Metrik-Filtering

Die Chart bringt Allowlists und Drop-Regeln fuer bestimmte Quellen mit. Das ist gut fuer Kostenkontrolle, aber die Regeln sind im Chart-Kontext verteilt. Ein Team-Mitglied muss wissen, ob eine Metrik im:

- Chart Feature,
- Destination Processor,
- `replaceComponent`,
- Prometheus Relabel,
- oder OTTL Filter

gedroppt wird.

## Vorteile des alten Ansatzes

| Vorteil | Bedeutung |
| --- | --- |
| Schneller Start | Viele Kubernetes-Quellen sind sofort verfuegbar. |
| Upstream-Wissen | Die Chart kennt typische Kubernetes-Monitoring-Quellen. |
| Gute Feature-Breite | Logs, Metrics, OTLP, Autodiscovery, ServiceMonitors usw. |
| Operator-Modell | Alloy CRs koennen getrennte Rollen wie `node` und `metrics` darstellen. |

## Nachteile des alten Ansatzes

| Nachteil | Auswirkung |
| --- | --- |
| Versteckte Komplexitaet | Die produktive River-Konfiguration ist schwer aus Values ableitbar. |
| `replaceComponent` Kopplung | Anpassungen haengen an chart-internen Namen und Strukturen. |
| Mehrfachpflege | Gemeinsame OTTL-Regeln muessen an mehreren Stellen synchron bleiben. |
| Schwerere Reviews | Diffs in Values zeigen nicht direkt, welche River-Config entsteht. |
| Upgrade-Risiko | Chart-Upgrades koennen interne Komponenten veraendern. |
| Weniger klare Ownership | Unklar, ob ein Verhalten Chart-Default oder Plattformentscheidung ist. |

## Was in das neue Noctua-Deployment uebernommen wurde

Die neue Architektur uebernimmt das Telemetry-Set, aber nicht den Generator-Ansatz:

| Altes Feature | Neuer Ort |
| --- | --- |
| Annotation Autodiscovery | `apps/alloy/noctua/files/alloy/annotation_autodiscovery_scrape.alloy` |
| Kubelet `/metrics` | `kubelet_scrape.alloy` |
| Kubelet `/metrics/resource` | `kubelet_resources_scrape.alloy` |
| cAdvisor | `cadvisor_scrape.alloy` |
| kube-state-metrics | `ksm_scrape.alloy` |
| node-exporter | `node_exporter_scrape.alloy` |
| kube-dns/CoreDNS | `kube_dns_scrape.alloy` |
| control-plane scrapes | `apiserver_scrape.alloy`, `controllermanager_scrape.alloy`, `scheduler_scrape.alloy`, `kubeproxy_scrape.alloy` |
| Pod Logs | `pod_logs_pipeline.alloy` plus `filelog` Receiver in `config.alloy` |
| OTLP App Telemetry | `application_pipeline.alloy` plus OTLP Receiver in `config.alloy` |
| Backend Destinations | `destinations.alloy` |
| Shared OTTL | `common_processing.alloy` und `templates/_ottl.tpl` |

## Migrationsergebnis

Das neue Noctua-Deployment ist nicht byte-identisch zum alten Render-Ergebnis. Das ist absichtlich. Es verfolgt Feature-Paritaet auf Datenquellen-Ebene:

- gleiche wichtigen Kubernetes-Metrics-Quellen,
- gleiche App-OTLP-Ingestion,
- gleiche Pod-Log-Ingestion,
- gleiche Backend-Ziele,
- aber explizite Module statt chart-generierter Blackbox.

Metric-Allowlists und Drops sind nicht ueberall exakt identisch. Stattdessen gibt es jetzt zwei klare Policy-Punkte:

- global: `alloyPipeline.metrics.globalDropRegex` und `globalKeepRegex`,
- target-spezifisch: `prometheus.relabel` im jeweiligen `*_scrape.alloy`.

## Wann `k8s-monitoring` trotzdem sinnvoll ist

Die Chart ist weiterhin eine gute Wahl, wenn:

- man schnell ein Standard-Kubernetes-Monitoring ohne starke eigene Policies braucht,
- das Team Chart-Defaults akzeptieren moechte,
- Upstream-Updates wichtiger sind als volle lokale Kontrolle,
- man keine eigene River-Modulstruktur pflegen moechte.

Fuer diese GitOps-Umgebung ist der modulare Alloy-Ansatz passender, weil Plattformentscheidungen explizit versioniert, reviewed und validiert werden koennen.
