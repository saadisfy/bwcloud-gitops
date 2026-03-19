# Alerting-Plan: Kubernetes Platform Alerting

Referenz fuer Infra-/Platform-Teams. Jeder Alert ist ein vollstaendiger Block
mit allen Feldern, die in der Grafana-Alerting-UI ausgefuellt werden muessen.

> Kontext: Produktiv-Setup mit mehreren Clustern, Argo CD, Kargo, Crossplane,
> Kyverno, Customer-Workloads. Dieses Repo ist ein kleineres Beispiel-Setup.

---

## Grafana Alerting UI -- Begriffe und Bedienung

### Was man in der Alert-Rules-Liste sieht (nur Anzeige, keine Eingabe)

| UI-Feld | Bedeutung | Werte |
|---|---|---|
| **State** | Aktueller Zustand der Rule | **Normal** = Bedingung nicht erfuellt. **Pending** = Bedingung erfuellt, aber `for`-Dauer noch nicht abgelaufen. **Firing** = Bedingung seit >= `for` erfuellt → Notification geht raus. **Recovering** = War Firing, Bedingung jetzt wieder OK. |
| **Rule type** | Art der Rule | **Alert** = loest Notification aus. **Recording** = berechnet eine Query vor und speichert das Ergebnis als neue Metrik (Performance-Optimierung, keine Notification). Fuer Alerting immer "Alert" waehlen. |
| **Health** | Evaluierungs-Gesundheit der Rule | **Ok** = Query laeuft fehlerfrei. **noData** = Query liefert keine Daten (z.B. Target nicht gescraped). **Error** = Query-Ausfuehrung fehlgeschlagen (z.B. Datasource down). |

### Wie man eine Alert Rule anlegt (Schritt fuer Schritt)

1. **Alerting → Alert rules → New alert rule**
2. **Rule name** eintragen
3. **Define query and alert condition**:
   - **Query A**: Datasource waehlen (z.B. "Mimir"), auf **"Code"** klicken, PromQL eintippen (nur die Query, **ohne** Vergleichsoperator wie `> 0.05` oder `== 0`)
   - **Expression B**: Unter der Query auf **"Add expression"** klicken → **Threshold** waehlen → Input: **A** → Operator und Wert setzen (z.B. "IS BELOW 1" oder "IS ABOVE 0.05")
   - **Alert condition** auf **B** setzen (Dropdown rechts am Expression-Block)
4. **Set evaluation behavior**:
   - **Folder**: Organisatorischer Ordner (z.B. "Cluster Health")
   - **Evaluation group**: Gruppe innerhalb des Folders (z.B. "Node Alerts") -- alle Rules einer Gruppe teilen sich das Evaluation Interval
   - **Evaluation interval**: Wie oft die Query ausgefuehrt wird (z.B. 1m)
   - **for**: Wie lange die Bedingung true sein muss bevor Pending → Firing
5. **Configure no data and error handling**:
   - **noDataState**: Was passiert wenn Query keine Daten liefert
   - **execErrState**: Was passiert bei Query-Fehler
6. **Add labels**: `severity`, `service`, `component` etc. -- werden fuer Notification-Routing verwendet
7. **Add annotations**: `summary` und `description` -- erscheinen im Alert-Text / E-Mail

### Severity (Label `severity`)

Severity ist kein eigenes UI-Feld, sondern ein **Label** das man beim Erstellen
der Rule unter "Add labels" setzt (`severity` = `critical` / `warning` / `info`).
Es bestimmt, wie der Alert geroutet und priorisiert wird.

| Severity | Bedeutung | Wann verwenden | Typische Reaktion |
|---|---|---|---|
| **critical** | Sofortige Aktion noetig, Service/Cluster direkt betroffen | Komplettausfall, Datenverlust droht, Deployments blockiert | Sofort reagieren, ggf. PagerDuty/On-Call |
| **warning** | Aufmerksamkeit noetig, aber noch kein Ausfall | Kapazitaet knapp, Performance-Degradation, einzelne Pods betroffen | Innerhalb von Stunden pruefen, Ticket erstellen |
| **info** | Zur Kenntnis, kein unmittelbarer Handlungsbedarf | Governance-Drift, neue Policy-Violations, Trends | Im naechsten Standup besprechen, Dashboard beobachten |

In der **Notification Policy** kann man anhand von `severity` routen:
z.B. `critical` → PagerDuty + E-Mail, `warning` → nur E-Mail,
`info` → nur Slack/Dashboard.

---

## Notification-Konzept (Vorschlag fuer dieses Setup)

Ziel: **schnell reagieren bei echten Stoerungen**, gleichzeitig **Alarm-Fatigue vermeiden**.

### 1) Kanaele (Startmodell: E-Mail only)

Fuer den Start werden nur E-Mail-Empfaenger genutzt:

1. **Direkt an Person** (primaere Verantwortung)
2. **E-Mail-Verteiler** (Team/Domain)
3. **Teams-Channel-E-Mail** (Transparenz im Teamkanal)

Damit ist Routing einfach und sofort umsetzbar, ohne Pager-Tooling.

### 2) Verantwortlichkeiten (aus euren Angaben)

| Bereich | Verantwortlich | Routing-Typ |
|---|---|---|
| DevExperience | **S** | direkte E-Mail + DevEx-Verteiler + DevEx-Teams-Channel |
| GitOps / Argo CD / Kargo | **GG** | direkte E-Mail + GitOps-Verteiler + GitOps-Teams-Channel |
| Crossplane | **L** | direkte E-Mail + Infra-Verteiler + Infra-Teams-Channel |
| Kyverno | **Verteiler** | nur Verteiler + Teams-Channel (kein Einzelowner als Primary) |
| Customer-Cluster (mit Kunden) | **M** | direkte E-Mail + Customer-Verteiler + Customer-Teams-Channel |
| Non-Customer-Cluster | **B** | direkte E-Mail + Platform-Verteiler + Platform-Teams-Channel |

### 3) Label-Strategie fuer korrektes Routing

Pflicht-Labels pro Alert:

- `severity`: `critical` / `warning` / `info`
- `service`: z.B. `argocd`, `kargo`, `crossplane`, `kyverno`, `kubernetes`
- `component`: Feingranularitaet

Zusaetzliche Routing-Labels (neu empfohlen):

- `domain`: `devexperience` | `gitops` | `customer`
- `clusterTier`: `customer` | `non-customer` (nur fuer Cluster-/Workload-Alerts)
- `owner`: `S` | `GG` | `L` | `M` | `B` | `distribution`

Damit kann die Notification Policy sehr praezise routen.

### 4) Routing-Matrix (wer bekommt was)

| Bedingung | Primaer | Sekundaer |
|---|---|---|
| `domain=devexperience` | S (direkt) | DevEx-Verteiler + DevEx-Teams-Mail |
| `service=argocd OR service=kargo` | GG (direkt) | GitOps-Verteiler + GitOps-Teams-Mail |
| `service=crossplane` | L (direkt) | Infra-Verteiler + Infra-Teams-Mail |
| `service=kyverno` | Kyverno-Verteiler | Security/Platform-Teams-Mail |
| `domain=customer AND clusterTier=customer` | M (direkt) | Customer-Verteiler + Customer-Teams-Mail |
| `domain=customer AND clusterTier=non-customer` | B (direkt) | Platform-Verteiler + Platform-Teams-Mail |

Fallback-Regel: Wenn kein Routing-Match greift → zentraler Platform-Verteiler + Platform-Teams-Mail.

### 5) Start-Best-Practice fuer Eskalation (ohne Pager)

Da nur E-Mail genutzt wird, erfolgt Eskalation ueber **Empfaenger-Erweiterung** und **Repeat**:

#### `critical`

- sofort: direkte Person + Verteiler + Teams-Channel-Mail
- `group_wait`: `30s`
- `group_interval`: `5m`
- `repeat_interval`: `30m`
- wenn nach 30 min noch firing: zusaetzlich Bereichs-Lead-Verteiler in Escalation-Route

#### `warning`

- sofort: direkte Person + Verteiler
- `group_wait`: `2m`
- `group_interval`: `15m`
- `repeat_interval`: `4h`
- Eskalation erst bei langer Dauer (z.B. > 1 Arbeitstag)

#### `info`

- nur Verteiler oder Teams-Channel-Mail
- `group_wait`: `5m`
- `group_interval`: `1h`
- `repeat_interval`: `24h`

### 6) noData / execErr Leitlinie

- Verfuegbarkeits-Checks (`up`, Control-Plane, Argo/Kargo Core): `noDataState: Alerting`
- Trend-/Mengen-Alerts: `noDataState: NoData` oder `OK`
- `execErrState` standardmaessig `Error`; bei hochkritischen Kontrollpunkten optional `Alerting`

### 7) Rollout-Vorgehen

1. **Woche 1-2:** nur severity + service/domain Routing, wenige Empfaenger
2. **Woche 3-4:** `clusterTier` sauber pflegen, Customer-Split M/B aktivieren
3. **ab Woche 5:** Repeat/Group-Werte anhand realer Last tunen

### 8) Definition of Done pro Alert

- `severity`, `service`, `component`, `domain` gesetzt
- fuer Cluster-/App-Alerts zusaetzlich `clusterTier` gesetzt
- Annotation mit klarer Handlung (`summary`, `description`, optional Runbook)
- Test: firing + resolve + korrekter Mail-Empfaengerpfad

---

## Uebersicht aller Alerts (Quick Reference)

### Cluster Health

| # | Alert | Query A (Code) | Expression B (Threshold) | Folder / Group | for | noData | execErr | Sev. |
|---|---|---|---|---|---|---|---|---|
| 1.1 | Node NotReady | `kube_node_status_condition{condition="Ready",status="true"}` | A IS BELOW 1 | Cluster Health / Node Alerts | 5m | Alerting | Error | critical |
| 1.2 | Node Disk Pressure | `kube_node_status_condition{condition="DiskPressure",status="true"}` | A IS ABOVE 0 | Cluster Health / Node Alerts | 5m | Alerting | Error | warning |
| 1.3 | Node Memory Pressure | `kube_node_status_condition{condition="MemoryPressure",status="true"}` | A IS ABOVE 0 | Cluster Health / Node Alerts | 5m | Alerting | Error | warning |
| 1.4 | Node PID Pressure | `kube_node_status_condition{condition="PIDPressure",status="true"}` | A IS ABOVE 0 | Cluster Health / Node Alerts | 5m | Alerting | Error | warning |
| 1.5 | Kubelet down | `up{job="kubelet"}` | A IS BELOW 1 | Cluster Health / Node Alerts | 5m | Alerting | Error | critical |
| 1.6 | API-Server Error Rate | `rate(apiserver_request_total{code=~"5.."}[5m]) / rate(apiserver_request_total[5m])` | A IS ABOVE 0.05 | Cluster Health / Control Plane | 5m | OK | Error | critical |
| 1.7 | API-Server Latency p99 | `histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m]))` | A IS ABOVE 4 | Cluster Health / Control Plane | 10m | OK | Error | warning |
| 1.8 | etcd Leader Changes | `increase(etcd_server_leader_changes_seen_total[1h])` | A IS ABOVE 3 | Cluster Health / Control Plane | 0s | OK | Error | critical |
| 1.9 | etcd Disk Fsync | `histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m]))` | A IS ABOVE 0.5 | Cluster Health / Control Plane | 10m | OK | Error | warning |
| 1.10 | CoreDNS down | `up{job="coredns"}` | A IS BELOW 1 | Cluster Health / Control Plane | 2m | Alerting | Error | critical |
| 1.11 | PV > 85% voll | `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes` | A IS ABOVE 0.85 | Cluster Health / Storage | 15m | OK | Error | warning |
| 1.12 | Pods stuck Pending | `kube_pod_status_phase{phase="Pending"}` | A IS ABOVE 0 | Cluster Health / Pod Health | 10m | NoData | Error | warning |
| 1.13 | CrashLoopBackOff | `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}` | A IS ABOVE 0 | Cluster Health / Pod Health | 15m | NoData | Error | warning |
| 1.14 | OOMKilled | `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` | A IS ABOVE 0 | Cluster Health / Pod Health | 0s | NoData | Error | warning |

### GitOps Pipeline (Argo CD)

| # | Alert | Query A (Code) | Expression B (Threshold) | Folder / Group | for | noData | execErr | Sev. |
|---|---|---|---|---|---|---|---|---|
| 2.1 | App Sync Failed | `argocd_app_info{sync_status="OutOfSync"}` | A IS ABOVE 0 | GitOps / Argo CD | 15m | NoData | Error | critical |
| 2.2 | App Health Degraded | `argocd_app_info{health_status="Degraded"}` | A IS ABOVE 0 | GitOps / Argo CD | 10m | NoData | Error | warning |
| 2.3 | App stuck Progressing | `argocd_app_info{health_status="Progressing"}` | A IS ABOVE 0 | GitOps / Argo CD | 30m | NoData | Error | warning |
| 2.4 | Repo-Server down | `up{job=~".*argocd-repo-server.*"}` | A IS BELOW 1 | GitOps / Argo CD | 5m | Alerting | Error | critical |
| 2.5 | AppSet Generation Error | `increase(argocd_applicationset_reconcile_errors_total[15m])` | A IS ABOVE 0 | GitOps / Argo CD | 0s | NoData | Error | warning |

### Promotion Pipeline (Kargo)

| # | Alert | Query A (Code) | Expression B (Threshold) | Folder / Group | for | noData | execErr | Sev. |
|---|---|---|---|---|---|---|---|---|
| 3.1 | Promotion Failed | `kargo_promotion_phase{phase="Failed"}` | A IS ABOVE 0 | Promotions / Kargo | 0s | NoData | Error | critical |
| 3.2 | Freight not verified | `kargo_freight_verified` | A IS BELOW 1 | Promotions / Kargo | 30m | NoData | Error | warning |
| 3.3 | Warehouse stale | `time() - kargo_warehouse_last_freight_timestamp` | A IS ABOVE 86400 | Promotions / Kargo | 0s | NoData | Error | warning |
| 3.4 | Stage unhealthy | `kargo_stage_health{health="Unhealthy"}` | A IS ABOVE 0 | Promotions / Kargo | 5m | NoData | Error | critical |

### Infrastructure-as-Code (Crossplane)

| # | Alert | Query A (Code) | Expression B (Threshold) | Folder / Group | for | noData | execErr | Sev. |
|---|---|---|---|---|---|---|---|---|
| 4.1 | Provider down | `up{job=~".*crossplane-provider.*"}` | A IS BELOW 1 | Infrastructure / Crossplane | 5m | Alerting | Error | critical |
| 4.2 | Managed Resource stuck | `crossplane_managed_resource_ready{status="False"}` | A IS ABOVE 0 | Infrastructure / Crossplane | 15m | NoData | Error | warning |
| 4.3 | Claim not bound | `crossplane_claim_ready{status="False"}` | A IS ABOVE 0 | Infrastructure / Crossplane | 10m | NoData | Error | warning |
| 4.4 | Deletion stuck | `time() - crossplane_managed_resource_deletion_timestamp` | A IS ABOVE 1800 | Infrastructure / Crossplane | 0s | NoData | Error | warning |

### Policy Engine (Kyverno)

| # | Alert | Query A (Code) | Expression B (Threshold) | Folder / Group | for | noData | execErr | Sev. |
|---|---|---|---|---|---|---|---|---|
| 5.1 | Webhook failures | `rate(kyverno_admission_requests_total{request_allowed="false"}[5m])` | A IS ABOVE 0 | Policy / Kyverno | 2m | Alerting | Alerting | critical |
| 5.2 | Controller down | `up{job=~".*kyverno.*"}` | A IS BELOW 1 | Policy / Kyverno | 5m | Alerting | Alerting | critical |
| 5.3 | Audit violation spike | `increase(kyverno_policy_results_total{rule_result="fail",policy_type="audit"}[1h])` | A IS ABOVE 10 | Policy / Kyverno | 0s | NoData | Error | warning |
| 5.4 | PolicyReport violations | `increase(kyverno_policy_report_results{status="fail"}[1h])` | A IS ABOVE 0 | Policy / Kyverno | 0s | NoData | Error | info |

### Observability Stack (Grafana, Mimir, OTel)

| # | Alert | Query A (Code) | Expression B (Threshold) | Folder / Group | for | noData | execErr | Sev. |
|---|---|---|---|---|---|---|---|---|
| 6.1 | Grafana down | `up{namespace=~"grafana.*", pod=~"grafana.*"}` | A IS BELOW 1 | Observability / Grafana | 5m | Alerting | Error | critical |
| 6.2 | Mimir Distributor down | `up{job=~".*mimir-distributor.*"}` | A IS BELOW 1 | Observability / Mimir | 5m | Alerting | Error | critical |
| 6.3 | Mimir Ingester down | `up{job=~".*mimir-ingester.*"}` | A IS BELOW 1 | Observability / Mimir | 5m | Alerting | Error | critical |
| 6.4 | Mimir Ingestion Drop | `rate(cortex_distributor_received_samples_total[5m]) / rate(cortex_distributor_received_samples_total[5m] offset 1h)` | A IS BELOW 0.5 | Observability / Mimir | 15m | OK | Error | warning |
| 6.5 | OTel Collector dropping | `increase(otelcol_exporter_send_failed_metric_points_total[5m])` | A IS ABOVE 0 | Observability / OTel | 5m | NoData | Error | warning |
| 6.6 | OTel Collector down | `up{job=~".*otel-collector.*"}` | A IS BELOW 1 | Observability / OTel | 5m | Alerting | Error | critical |

### Ingress & Networking

| # | Alert | Query A (Code) | Expression B (Threshold) | Folder / Group | for | noData | execErr | Sev. |
|---|---|---|---|---|---|---|---|---|
| 7.1 | 5xx Rate > 5% | `rate(nginx_ingress_controller_requests{status=~"5.."}[5m]) / rate(nginx_ingress_controller_requests[5m])` | A IS ABOVE 0.05 | Networking / Ingress | 5m | OK | Error | critical |
| 7.2 | p99 Latency > 5s | `histogram_quantile(0.99, rate(nginx_ingress_controller_request_duration_seconds_bucket[5m]))` | A IS ABOVE 5 | Networking / Ingress | 10m | OK | Error | warning |
| 7.3 | Backend 502 | `increase(nginx_ingress_controller_upstream_server_responses{status_code="502"}[5m])` | A IS ABOVE 0 | Networking / Ingress | 5m | NoData | Error | warning |

### Certificate Management (cert-manager)

| # | Alert | Query A (Code) | Expression B (Threshold) | Folder / Group | for | noData | execErr | Sev. |
|---|---|---|---|---|---|---|---|---|
| 8.1 | Cert expires < 14d | `certmanager_certificate_expiration_timestamp_seconds - time()` | A IS BELOW 1209600 | Networking / Certificates | 0s | NoData | Error | warning |
| 8.2 | Cert Renewal failed | `certmanager_certificate_ready_status{condition="False"}` | A IS ABOVE 0 | Networking / Certificates | 1h | NoData | Error | critical |
| 8.3 | ClusterIssuer not Ready | `certmanager_clusterissuer_ready{condition="False"}` | A IS ABOVE 0 | Networking / Certificates | 5m | Alerting | Error | critical |

### Customer Applications

| # | Alert | Query A (Code) | Expression B (Threshold) | Folder / Group | for | noData | execErr | Sev. |
|---|---|---|---|---|---|---|---|---|
| 9.1 | Rollout stuck | `kube_deployment_status_condition{condition="Progressing",status="false"}` | A IS ABOVE 0 | Applications / Deployments | 15m | NoData | Error | warning |
| 9.2 | HPA at Max | `kube_horizontalpodautoscaler_status_current_replicas / kube_horizontalpodautoscaler_spec_max_replicas` | A IS ABOVE 0.99 | Applications / Scaling | 30m | NoData | Error | warning |
| 9.3 | Quota > 90% | `kube_resourcequota{type="used"} / kube_resourcequota{type="hard"}` | A IS ABOVE 0.9 | Applications / Scaling | 15m | OK | Error | warning |
| 9.4 | Pod Restarts > 5/h | `increase(kube_pod_container_status_restarts_total[1h])` | A IS ABOVE 5 | Applications / Deployments | 0s | NoData | Error | warning |

---

## Detail-Bloecke (alle UI-Felder pro Alert)

## 1. Cluster Health

Metriken von **kube-state-metrics** und **node-exporter**.

### 1.1 Node NotReady

- **Rule name:** Node NotReady
- **Datasource:** Mimir
- **Query A (Code):** `kube_node_status_condition{condition="Ready",status="true"}`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Node Alerts
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `kubernetes`
  - `component` = `node`
- **Annotations:**
  - summary: `Node {{ $labels.node }} is NotReady`
  - description: `Node {{ $labels.node }} ist seit > 5 Minuten nicht Ready. Workloads werden evtl. evicted.`

### 1.2 Node Disk Pressure

- **Rule name:** Node Disk Pressure
- **Datasource:** Mimir
- **Query A (Code):** `kube_node_status_condition{condition="DiskPressure",status="true"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Node Alerts
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kubernetes`
  - `component` = `node`
- **Annotations:**
  - summary: `Node {{ $labels.node }} has disk pressure`
  - description: `Node {{ $labels.node }} meldet DiskPressure. Evictions drohen.`

### 1.3 Node Memory Pressure

- **Rule name:** Node Memory Pressure
- **Datasource:** Mimir
- **Query A (Code):** `kube_node_status_condition{condition="MemoryPressure",status="true"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Node Alerts
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kubernetes`
  - `component` = `node`
- **Annotations:**
  - summary: `Node {{ $labels.node }} has memory pressure`
  - description: `Node {{ $labels.node }} meldet MemoryPressure. OOM-Kills drohen.`

### 1.4 Node PID Pressure

- **Rule name:** Node PID Pressure
- **Datasource:** Mimir
- **Query A (Code):** `kube_node_status_condition{condition="PIDPressure",status="true"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Node Alerts
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kubernetes`
  - `component` = `node`
- **Annotations:**
  - summary: `Node {{ $labels.node }} has PID pressure`
  - description: `Node {{ $labels.node }} meldet PIDPressure. Prozess-Limit erreicht.`

### 1.5 Kubelet down

- **Rule name:** Kubelet down
- **Datasource:** Mimir
- **Query A (Code):** `up{job="kubelet"}`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Node Alerts
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `kubernetes`
  - `component` = `kubelet`
- **Annotations:**
  - summary: `Kubelet on {{ $labels.instance }} is down`
  - description: `Kubelet auf {{ $labels.instance }} ist seit > 5 Min nicht erreichbar. Node ist effektiv tot.`

### 1.6 API-Server Error Rate

- **Rule name:** API-Server Error Rate > 5%
- **Datasource:** Mimir
- **Query A (Code):** `rate(apiserver_request_total{code=~"5.."}[5m]) / rate(apiserver_request_total[5m])`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0.05**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Control Plane
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** OK
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `kubernetes`
  - `component` = `apiserver`
- **Annotations:**
  - summary: `API-Server error rate > 5%`
  - description: `Mehr als 5% der API-Server-Requests liefern 5xx. Control-Plane-Degradation.`

### 1.7 API-Server Latency p99

- **Rule name:** API-Server Latency p99 > 4s
- **Datasource:** Mimir
- **Query A (Code):** `histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m]))`
- **Expression B:** Threshold | Input: A | **IS ABOVE 4**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Control Plane
- **Evaluation interval:** 1m
- **for:** 10m
- **noDataState:** OK
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kubernetes`
  - `component` = `apiserver`
- **Annotations:**
  - summary: `API-Server p99 latency > 4s`
  - description: `API-Server-Requests dauern p99 > 4 Sekunden. Control Plane ist langsam.`

### 1.8 etcd Leader Changes

- **Rule name:** etcd excessive leader changes
- **Datasource:** Mimir
- **Query A (Code):** `increase(etcd_server_leader_changes_seen_total[1h])`
- **Expression B:** Threshold | Input: A | **IS ABOVE 3**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Control Plane
- **Evaluation interval:** 1m
- **for:** 0s
- **noDataState:** OK
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `kubernetes`
  - `component` = `etcd`
- **Annotations:**
  - summary: `etcd had > 3 leader changes in 1h`
  - description: `etcd zeigt ueberdurchschnittlich viele Leader-Wechsel. Cluster ist instabil.`

### 1.9 etcd Disk Fsync

- **Rule name:** etcd slow disk fsync
- **Datasource:** Mimir
- **Query A (Code):** `histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m]))`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0.5**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Control Plane
- **Evaluation interval:** 1m
- **for:** 10m
- **noDataState:** OK
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kubernetes`
  - `component` = `etcd`
- **Annotations:**
  - summary: `etcd WAL fsync p99 > 500ms`
  - description: `etcd-Disk ist langsam (WAL fsync p99 > 0.5s). Kann zu Leader-Verlust fuehren.`

### 1.10 CoreDNS down

- **Rule name:** CoreDNS down
- **Datasource:** Mimir
- **Query A (Code):** `up{job="coredns"}`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Control Plane
- **Evaluation interval:** 1m
- **for:** 2m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `kubernetes`
  - `component` = `coredns`
- **Annotations:**
  - summary: `CoreDNS is down`
  - description: `CoreDNS ist nicht erreichbar. Service-Discovery ist kaputt, DNS-Aufloesung im Cluster faellt aus.`

### 1.11 PersistentVolume > 85% voll

- **Rule name:** PV usage > 85%
- **Datasource:** Mimir
- **Query A (Code):** `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0.85**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Storage
- **Evaluation interval:** 5m
- **for:** 15m
- **noDataState:** OK
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kubernetes`
  - `component` = `storage`
- **Annotations:**
  - summary: `PV {{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }} > 85% full`
  - description: `PersistentVolumeClaim {{ $labels.persistentvolumeclaim }} in Namespace {{ $labels.namespace }} ist zu > 85% belegt. Datenverlust oder App-Crash droht.`

### 1.12 Pods stuck Pending

- **Rule name:** Pod stuck in Pending
- **Datasource:** Mimir
- **Query A (Code):** `kube_pod_status_phase{phase="Pending"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Pod Health
- **Evaluation interval:** 1m
- **for:** 10m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kubernetes`
  - `component` = `scheduling`
- **Annotations:**
  - summary: `Pod {{ $labels.pod }} in {{ $labels.namespace }} stuck Pending`
  - description: `Pod {{ $labels.pod }} haengt seit > 10 Min in Pending. Moegliche Ursachen: fehlende Ressourcen, Taints, PVC nicht gebunden.`

### 1.13 CrashLoopBackOff

- **Rule name:** CrashLoopBackOff
- **Datasource:** Mimir
- **Query A (Code):** `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Pod Health
- **Evaluation interval:** 1m
- **for:** 15m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kubernetes`
  - `component` = `pod`
- **Annotations:**
  - summary: `Container {{ $labels.container }} in {{ $labels.namespace }}/{{ $labels.pod }} is CrashLooping`
  - description: `Container {{ $labels.container }} im Pod {{ $labels.pod }} (Namespace {{ $labels.namespace }}) ist seit > 15 Min in CrashLoopBackOff.`

### 1.14 OOMKilled Pods

- **Rule name:** OOMKilled
- **Datasource:** Mimir
- **Query A (Code):** `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Cluster Health
- **Evaluation group:** Pod Health
- **Evaluation interval:** 1m
- **for:** 0s
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kubernetes`
  - `component` = `pod`
- **Annotations:**
  - summary: `Container {{ $labels.container }} in {{ $labels.namespace }}/{{ $labels.pod }} was OOMKilled`
  - description: `Container {{ $labels.container }} im Pod {{ $labels.pod }} wurde wegen Out-of-Memory gekillt. Memory-Limits erhoehen oder Memory-Leak fixen.`

---

## 2. GitOps Pipeline (Argo CD)

Metriken vom Argo CD metrics endpoint. Bei mehreren Argo-Instanzen:
`namespace`-Label im PromQL filtern.

### 2.1 Application Sync Failed

- **Rule name:** Argo CD App OutOfSync
- **Datasource:** Mimir
- **Query A (Code):** `argocd_app_info{sync_status="OutOfSync"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** GitOps
- **Evaluation group:** Argo CD
- **Evaluation interval:** 1m
- **for:** 15m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `argocd`
  - `component` = `application`
- **Annotations:**
  - summary: `Argo CD App {{ $labels.name }} is OutOfSync`
  - description: `Application {{ $labels.name }} (Projekt {{ $labels.project }}) ist seit > 15 Min OutOfSync. Desired State != Actual State.`

### 2.2 Application Health Degraded

- **Rule name:** Argo CD App Degraded
- **Datasource:** Mimir
- **Query A (Code):** `argocd_app_info{health_status="Degraded"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** GitOps
- **Evaluation group:** Argo CD
- **Evaluation interval:** 1m
- **for:** 10m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `argocd`
  - `component` = `application`
- **Annotations:**
  - summary: `Argo CD App {{ $labels.name }} is Degraded`
  - description: `Application {{ $labels.name }} ist seit > 10 Min Degraded. Teilweise kaputt.`

### 2.3 Application stuck Progressing

- **Rule name:** Argo CD App stuck Progressing
- **Datasource:** Mimir
- **Query A (Code):** `argocd_app_info{health_status="Progressing"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** GitOps
- **Evaluation group:** Argo CD
- **Evaluation interval:** 1m
- **for:** 30m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `argocd`
  - `component` = `application`
- **Annotations:**
  - summary: `Argo CD App {{ $labels.name }} stuck Progressing`
  - description: `Application {{ $labels.name }} haengt seit > 30 Min in Progressing. Rollout blockiert (Image-Pull, Readiness-Probe, Resource-Limit).`

### 2.4 Repo-Server down

- **Rule name:** Argo CD Repo-Server down
- **Datasource:** Mimir
- **Query A (Code):** `up{job=~".*argocd-repo-server.*"}`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** GitOps
- **Evaluation group:** Argo CD
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `argocd`
  - `component` = `repo-server`
- **Annotations:**
  - summary: `Argo CD Repo-Server is down`
  - description: `Argo CD Repo-Server ist nicht erreichbar. Kein Git-Zugriff moeglich, keine Syncs.`

### 2.5 ApplicationSet Generation Error

- **Rule name:** Argo CD AppSet reconcile errors
- **Datasource:** Mimir
- **Query A (Code):** `increase(argocd_applicationset_reconcile_errors_total[15m])`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** GitOps
- **Evaluation group:** Argo CD
- **Evaluation interval:** 1m
- **for:** 0s
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `argocd`
  - `component` = `applicationset`
- **Annotations:**
  - summary: `ApplicationSet reconcile errors detected`
  - description: `ApplicationSet-Controller hat Reconcile-Fehler. Neue Applications werden moeglicherweise nicht erzeugt.`

---

## 3. Promotion Pipeline (Kargo)

Metriken vom Kargo Controller. Exakte Metrik-Namen pruefen:
`kubectl get --raw /metrics` am Kargo-Controller-Pod.

### 3.1 Promotion Failed

- **Rule name:** Kargo Promotion Failed
- **Datasource:** Mimir
- **Query A (Code):** `kargo_promotion_phase{phase="Failed"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Promotions
- **Evaluation group:** Kargo
- **Evaluation interval:** 1m
- **for:** 0s
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `kargo`
  - `component` = `promotion`
- **Annotations:**
  - summary: `Kargo Promotion failed in {{ $labels.namespace }}`
  - description: `Eine Kargo-Promotion ist fehlgeschlagen. Release-Pipeline ist blockiert. Freight und Stage-Logs pruefen.`

### 3.2 Freight Verification Failed

- **Rule name:** Kargo Freight not verified
- **Datasource:** Mimir
- **Query A (Code):** `kargo_freight_verified`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** Promotions
- **Evaluation group:** Kargo
- **Evaluation interval:** 5m
- **for:** 30m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kargo`
  - `component` = `freight`
- **Annotations:**
  - summary: `Kargo Freight unverified for > 30m`
  - description: `Freight wurde seit > 30 Min nicht verifiziert. Schlechtes Artefakt oder fehlgeschlagene Verification.`

### 3.3 Warehouse stale

- **Rule name:** Kargo Warehouse stale (no new freight)
- **Datasource:** Mimir
- **Query A (Code):** `time() - kargo_warehouse_last_freight_timestamp`
- **Expression B:** Threshold | Input: A | **IS ABOVE 86400**
- **Alert condition:** B
- **Folder:** Promotions
- **Evaluation group:** Kargo
- **Evaluation interval:** 5m
- **for:** 0s
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kargo`
  - `component` = `warehouse`
- **Annotations:**
  - summary: `Kargo Warehouse has no new freight for > 24h`
  - description: `Warehouse hat seit > 24h keinen neuen Freight entdeckt. Upstream-Repo, Registry oder Warehouse-Config pruefen.`

### 3.4 Stage Unhealthy

- **Rule name:** Kargo Stage unhealthy
- **Datasource:** Mimir
- **Query A (Code):** `kargo_stage_health{health="Unhealthy"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Promotions
- **Evaluation group:** Kargo
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `kargo`
  - `component` = `stage`
- **Annotations:**
  - summary: `Kargo Stage {{ $labels.stage }} is unhealthy`
  - description: `Stage {{ $labels.stage }} (Projekt {{ $labels.namespace }}) ist nach Promotion unhealthy. Zielumgebung pruefen.`

---

## 4. Infrastructure-as-Code (Crossplane)

Metriken vom Crossplane Controller und ggf. kube-state-metrics
Custom-Resource-Metriken. Metriken variieren je nach Provider-Version.

### 4.1 Provider Pod unhealthy

- **Rule name:** Crossplane Provider down
- **Datasource:** Mimir
- **Query A (Code):** `up{job=~".*crossplane-provider.*"}`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** Infrastructure
- **Evaluation group:** Crossplane
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `crossplane`
  - `component` = `provider`
- **Annotations:**
  - summary: `Crossplane Provider {{ $labels.job }} is down`
  - description: `Crossplane-Provider ist nicht erreichbar. Keine Cloud-Ressourcen koennen reconciled werden.`

### 4.2 Managed Resource not Ready

- **Rule name:** Crossplane Managed Resource stuck
- **Datasource:** Mimir
- **Query A (Code):** `crossplane_managed_resource_ready{status="False"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Infrastructure
- **Evaluation group:** Crossplane
- **Evaluation interval:** 1m
- **for:** 15m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `crossplane`
  - `component` = `managed-resource`
- **Annotations:**
  - summary: `Managed Resource in {{ $labels.namespace }} not ready for > 15m`
  - description: `Cloud-Ressource haengt seit > 15 Min beim Erstellen/Updaten. Provider-Logs und Cloud-API-Limits pruefen.`

### 4.3 Claim not Bound

- **Rule name:** Crossplane Claim not bound
- **Datasource:** Mimir
- **Query A (Code):** `crossplane_claim_ready{status="False"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Infrastructure
- **Evaluation group:** Crossplane
- **Evaluation interval:** 1m
- **for:** 10m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `crossplane`
  - `component` = `claim`
- **Annotations:**
  - summary: `Crossplane Claim in {{ $labels.namespace }} not bound`
  - description: `Developer-facing Claim ist seit > 10 Min nicht gebunden. Composition oder Provider-Config pruefen.`

### 4.4 Managed Resource Deletion stuck

- **Rule name:** Crossplane deletion stuck
- **Datasource:** Mimir
- **Query A (Code):** `time() - crossplane_managed_resource_deletion_timestamp`
- **Expression B:** Threshold | Input: A | **IS ABOVE 1800**
- **Alert condition:** B
- **Folder:** Infrastructure
- **Evaluation group:** Crossplane
- **Evaluation interval:** 5m
- **for:** 0s
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `crossplane`
  - `component` = `managed-resource`
- **Annotations:**
  - summary: `Managed Resource deletion stuck > 30m`
  - description: `Eine Crossplane Managed Resource haengt beim Loeschen. Orphaned Cloud-Ressourcen = Kostenrisiko. Finalizer und Provider-Logs pruefen.`

---

## 5. Policy Engine (Kyverno)

Metriken vom Kyverno Controller metrics endpoint.

> **Wichtig:** Ein kaputter Kyverno-Webhook im Fail-Modus blockiert
> die gesamte Deployment-Pipeline. Deshalb: `noDataState: Alerting`
> und `execErrState: Alerting` -- lieber false-positive als stille Blockade.

### 5.1 Webhook Failure

- **Rule name:** Kyverno Webhook failures
- **Datasource:** Mimir
- **Query A (Code):** `rate(kyverno_admission_requests_total{request_allowed="false"}[5m])`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Policy
- **Evaluation group:** Kyverno
- **Evaluation interval:** 1m
- **for:** 2m
- **noDataState:** Alerting
- **execErrState:** Alerting
- **Labels:**
  - `severity` = `critical`
  - `service` = `kyverno`
  - `component` = `webhook`
- **Annotations:**
  - summary: `Kyverno Webhook is rejecting requests`
  - description: `Kyverno-Webhook lehnt Admission-Requests ab. Bei Fail-Closed-Mode sind alle Deployments blockiert. Kyverno-Controller-Logs sofort pruefen.`

### 5.2 Controller unhealthy

- **Rule name:** Kyverno Controller down
- **Datasource:** Mimir
- **Query A (Code):** `up{job=~".*kyverno.*"}`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** Policy
- **Evaluation group:** Kyverno
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Alerting
- **Labels:**
  - `severity` = `critical`
  - `service` = `kyverno`
  - `component` = `controller`
- **Annotations:**
  - summary: `Kyverno Controller is down`
  - description: `Kyverno-Controller ist nicht erreichbar. Policies werden nicht enforced. Bei Fail-Closed droht Deployment-Blockade.`

### 5.3 Audit Violation Spike

- **Rule name:** Kyverno audit violation spike
- **Datasource:** Mimir
- **Query A (Code):** `increase(kyverno_policy_results_total{rule_result="fail",policy_type="audit"}[1h])`
- **Expression B:** Threshold | Input: A | **IS ABOVE 10**
- **Alert condition:** B
- **Folder:** Policy
- **Evaluation group:** Kyverno
- **Evaluation interval:** 5m
- **for:** 0s
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `kyverno`
  - `component` = `policy`
- **Annotations:**
  - summary: `> 10 Kyverno audit violations in 1h`
  - description: `Ueberdurchschnittlich viele Policy-Violations im Audit-Modus. Etwas driftet von Policy ab. PolicyReports pruefen.`

### 5.4 PolicyReport new Violations

- **Rule name:** Kyverno PolicyReport violations
- **Datasource:** Mimir
- **Query A (Code):** `increase(kyverno_policy_report_results{status="fail"}[1h])`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Policy
- **Evaluation group:** Kyverno
- **Evaluation interval:** 5m
- **for:** 0s
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `info`
  - `service` = `kyverno`
  - `component` = `policyreport`
- **Annotations:**
  - summary: `New Kyverno PolicyReport violations`
  - description: `Neue Policy-Violations in PolicyReports entdeckt. Governance-Regression pruefen.`

---

## 6. Observability Stack (Grafana, Mimir, OTel)

### 6.1 Grafana unhealthy

- **Rule name:** Grafana down
- **Datasource:** Mimir
- **Query A (Code):** `up{namespace=~"grafana.*", pod=~"grafana.*"}`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** Observability
- **Evaluation group:** Grafana
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `grafana`
  - `component` = `server`
- **Annotations:**
  - summary: `Grafana is down in {{ $labels.namespace }}`
  - description: `Grafana-Pod in {{ $labels.namespace }} ist nicht erreichbar. Monitoring-UI nicht verfuegbar.`

### 6.2 Mimir Distributor down

- **Rule name:** Mimir Distributor down
- **Datasource:** Mimir
- **Query A (Code):** `up{job=~".*mimir-distributor.*"}`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** Observability
- **Evaluation group:** Mimir
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `mimir`
  - `component` = `distributor`
- **Annotations:**
  - summary: `Mimir Distributor is down`
  - description: `Mimir Distributor ist nicht erreichbar. Metrics-Pipeline-Eingang ist kaputt, keine neuen Metriken werden angenommen.`

### 6.3 Mimir Ingester down

- **Rule name:** Mimir Ingester down
- **Datasource:** Mimir
- **Query A (Code):** `up{job=~".*mimir-ingester.*"}`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** Observability
- **Evaluation group:** Mimir
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `mimir`
  - `component` = `ingester`
- **Annotations:**
  - summary: `Mimir Ingester is down`
  - description: `Mimir Ingester ist nicht erreichbar. Metrics-Speicher kaputt, Datenverlust moeglich.`

### 6.4 Mimir Ingestion Rate Drop > 50%

- **Rule name:** Mimir ingestion rate drop
- **Datasource:** Mimir
- **Query A (Code):** `rate(cortex_distributor_received_samples_total[5m]) / rate(cortex_distributor_received_samples_total[5m] offset 1h)`
- **Expression B:** Threshold | Input: A | **IS BELOW 0.5**
- **Alert condition:** B
- **Folder:** Observability
- **Evaluation group:** Mimir
- **Evaluation interval:** 1m
- **for:** 15m
- **noDataState:** OK
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `mimir`
  - `component` = `pipeline`
- **Annotations:**
  - summary: `Mimir ingestion rate dropped > 50%`
  - description: `Mimir nimmt deutlich weniger Samples an als vor 1h. Pipeline ist moeglicherweise leise kaputt (OTel Collector, Scrape-Targets).`

### 6.5 OTel Collector dropping data

- **Rule name:** OTel Collector send failures
- **Datasource:** Mimir
- **Query A (Code):** `increase(otelcol_exporter_send_failed_metric_points_total[5m])`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Observability
- **Evaluation group:** OTel
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `otel`
  - `component` = `collector`
- **Annotations:**
  - summary: `OTel Collector is dropping metric data`
  - description: `OTel Collector konnte Metriken nicht exportieren (Queue voll oder Backend unerreichbar). Telemetrie geht verloren.`

### 6.6 OTel Collector down

- **Rule name:** OTel Collector down
- **Datasource:** Mimir
- **Query A (Code):** `up{job=~".*otel-collector.*"}`
- **Expression B:** Threshold | Input: A | **IS BELOW 1**
- **Alert condition:** B
- **Folder:** Observability
- **Evaluation group:** OTel
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `otel`
  - `component` = `collector`
- **Annotations:**
  - summary: `OTel Collector is down`
  - description: `OTel Collector-Pod ist nicht erreichbar. Kein Telemetrie-Empfang (Metrics, Traces, Logs).`

---

## 7. Ingress & Networking

Metriken vom nginx-ingress-controller metrics endpoint.

### 7.1 5xx Rate Spike

- **Rule name:** Ingress 5xx error rate > 5%
- **Datasource:** Mimir
- **Query A (Code):** `rate(nginx_ingress_controller_requests{status=~"5.."}[5m]) / rate(nginx_ingress_controller_requests[5m])`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0.05**
- **Alert condition:** B
- **Folder:** Networking
- **Evaluation group:** Ingress
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** OK
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `ingress`
  - `component` = `nginx`
- **Annotations:**
  - summary: `Ingress 5xx rate > 5%`
  - description: `Mehr als 5% der Ingress-Requests liefern 5xx. User-facing Errors.`

### 7.2 p99 Latency > 5s

- **Rule name:** Ingress p99 latency > 5s
- **Datasource:** Mimir
- **Query A (Code):** `histogram_quantile(0.99, rate(nginx_ingress_controller_request_duration_seconds_bucket[5m]))`
- **Expression B:** Threshold | Input: A | **IS ABOVE 5**
- **Alert condition:** B
- **Folder:** Networking
- **Evaluation group:** Ingress
- **Evaluation interval:** 1m
- **for:** 10m
- **noDataState:** OK
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `ingress`
  - `component` = `nginx`
- **Annotations:**
  - summary: `Ingress p99 latency > 5 seconds`
  - description: `Ingress-Controller p99-Latenz ist ueber 5 Sekunden. Performance-Degradation fuer User.`

### 7.3 Backend unreachable (502)

- **Rule name:** Ingress backend 502 errors
- **Datasource:** Mimir
- **Query A (Code):** `increase(nginx_ingress_controller_upstream_server_responses{status_code="502"}[5m])`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Networking
- **Evaluation group:** Ingress
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `ingress`
  - `component` = `upstream`
- **Annotations:**
  - summary: `Ingress backend returning 502`
  - description: `Backend-Service hinter dem Ingress ist nicht erreichbar (502 Bad Gateway). Service-Health und Ingress-Config pruefen.`

---

## 8. Certificate Management (cert-manager)

Metriken vom cert-manager controller.

### 8.1 Certificate expires < 14 Tage

- **Rule name:** Certificate expiring soon
- **Datasource:** Mimir
- **Query A (Code):** `certmanager_certificate_expiration_timestamp_seconds - time()`
- **Expression B:** Threshold | Input: A | **IS BELOW 1209600**
- **Alert condition:** B
- **Folder:** Networking
- **Evaluation group:** Certificates
- **Evaluation interval:** 5m
- **for:** 0s
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `cert-manager`
  - `component` = `certificate`
- **Annotations:**
  - summary: `Certificate {{ $labels.name }} in {{ $labels.namespace }} expires in < 14 days`
  - description: `TLS-Zertifikat {{ $labels.name }} laeuft in weniger als 14 Tagen ab. Automatische Erneuerung pruefen.`

### 8.2 Certificate Renewal failed

- **Rule name:** Certificate renewal failed
- **Datasource:** Mimir
- **Query A (Code):** `certmanager_certificate_ready_status{condition="False"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Networking
- **Evaluation group:** Certificates
- **Evaluation interval:** 1m
- **for:** 1h
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `cert-manager`
  - `component` = `certificate`
- **Annotations:**
  - summary: `Certificate {{ $labels.name }} in {{ $labels.namespace }} renewal failed`
  - description: `Zertifikat {{ $labels.name }} ist seit > 1h nicht Ready. Automatische Erneuerung fehlgeschlagen. cert-manager Logs und ACME-Challenges pruefen.`

### 8.3 ClusterIssuer not Ready

- **Rule name:** ClusterIssuer not ready
- **Datasource:** Mimir
- **Query A (Code):** `certmanager_clusterissuer_ready{condition="False"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Networking
- **Evaluation group:** Certificates
- **Evaluation interval:** 1m
- **for:** 5m
- **noDataState:** Alerting
- **execErrState:** Error
- **Labels:**
  - `severity` = `critical`
  - `service` = `cert-manager`
  - `component` = `issuer`
- **Annotations:**
  - summary: `ClusterIssuer {{ $labels.name }} is not ready`
  - description: `ClusterIssuer {{ $labels.name }} ist nicht Ready. Keine neuen Zertifikate koennen ausgestellt werden.`

---

## 9. Customer Applications (generisch / cross-cutting)

Metriken von kube-state-metrics.

### 9.1 Deployment Rollout stuck

- **Rule name:** Deployment rollout stuck
- **Datasource:** Mimir
- **Query A (Code):** `kube_deployment_status_condition{condition="Progressing",status="false"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0**
- **Alert condition:** B
- **Folder:** Applications
- **Evaluation group:** Deployments
- **Evaluation interval:** 1m
- **for:** 15m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `application`
  - `component` = `deployment`
- **Annotations:**
  - summary: `Deployment {{ $labels.deployment }} in {{ $labels.namespace }} rollout stuck`
  - description: `Deployment {{ $labels.deployment }} (Namespace {{ $labels.namespace }}) haengt seit > 15 Min beim Rollout. Image-Pull, Readiness-Probes, Resource-Limits pruefen.`

### 9.2 HPA at Max Replicas

- **Rule name:** HPA at max replicas
- **Datasource:** Mimir
- **Query A (Code):** `kube_horizontalpodautoscaler_status_current_replicas / kube_horizontalpodautoscaler_spec_max_replicas`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0.99**
- **Alert condition:** B
- **Folder:** Applications
- **Evaluation group:** Scaling
- **Evaluation interval:** 1m
- **for:** 30m
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `application`
  - `component` = `hpa`
- **Annotations:**
  - summary: `HPA {{ $labels.horizontalpodautoscaler }} in {{ $labels.namespace }} at max replicas`
  - description: `HPA {{ $labels.horizontalpodautoscaler }} laeuft seit > 30 Min auf Maximum. App kann nicht weiter skalieren, Performance-Degradation moeglich.`

### 9.3 ResourceQuota > 90%

- **Rule name:** ResourceQuota > 90%
- **Datasource:** Mimir
- **Query A (Code):** `kube_resourcequota{type="used"} / kube_resourcequota{type="hard"}`
- **Expression B:** Threshold | Input: A | **IS ABOVE 0.9**
- **Alert condition:** B
- **Folder:** Applications
- **Evaluation group:** Scaling
- **Evaluation interval:** 5m
- **for:** 15m
- **noDataState:** OK
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `application`
  - `component` = `quota`
- **Annotations:**
  - summary: `ResourceQuota {{ $labels.resourcequota }} in {{ $labels.namespace }} > 90%`
  - description: `Namespace {{ $labels.namespace }} hat > 90% der ResourceQuota {{ $labels.resourcequota }} verbraucht. Team stoesst an Limits.`

### 9.4 Pod Restart Count > 5 in 1h

- **Rule name:** Pod flapping (> 5 restarts/h)
- **Datasource:** Mimir
- **Query A (Code):** `increase(kube_pod_container_status_restarts_total[1h])`
- **Expression B:** Threshold | Input: A | **IS ABOVE 5**
- **Alert condition:** B
f- **Folder:** Applications
- **Evaluation group:** Deployments
- **Evaluation interval:** 1m
- **for:** 0s
- **noDataState:** NoData
- **execErrState:** Error
- **Labels:**
  - `severity` = `warning`
  - `service` = `application`
  - `component` = `pod`
- **Annotations:**
  - summary: `Container {{ $labels.container }} in {{ $labels.namespace }}/{{ $labels.pod }} restarted > 5 times in 1h`
  - description: `Container {{ $labels.container }} im Pod {{ $labels.pod }} (Namespace {{ $labels.namespace }}) wurde > 5x in 1h neugestartet. Flapping Workload, Logs pruefen.`

---

## Priorisierung (Empfehlung)

**Day 1 (sofort):**

- Cluster Health (Node, kubelet, etcd, CoreDNS)
- Argo CD (Sync Failed, Repo-Server)
- Kyverno Webhook Failures
- cert-manager Certificate Expiry

**Day 2 (kurzfristig):**

- Kargo Promotion Failed
- Observability Stack (Mimir, OTel Collector)
- Ingress 5xx Rate

**Day 3 (mittelfristig):**

- Crossplane Provider/Resource Health
- Customer Application Alerts
- Kyverno Audit Violations
- HPA / ResourceQuota Alerts

---

## Offene Entscheidungen

1. **Notification-Kanal:** Nur E-Mail oder auch Slack/Teams/PagerDuty?
2. **Per-Cluster vs. zentral:** Ein Grafana Operator pro Cluster mit lokalen CRs, oder ein zentrales Grafana fuer alle Cluster?
3. **Routing nach Team:** Infra-Team bekommt Cluster/Argo/Kargo-Alerts, App-Teams ihre eigenen Namespace-Alerts?
4. **Metriken-Verfuegbarkeit:** `kubectl get --raw /metrics` an den jeweiligen Controllern pruefen (besonders Kargo, Crossplane).
