# Observability Plattform — Testkonzept

Dieses Dokument beschreibt das Testkonzept für die Observability-Plattform bestehend aus
**Mimir**, **Alloy** und **Grafana**, deployed über Argo CD.

---

## 1. Testhierarchie

```
┌─────────────────────────────────────────────────────────────────┐
│  Ebene 4: Blackbox E2E                                          │
│  Vollständige Pipeline aus Nutzerperspektive                    │
│  "Ich sehe Metriken im Grafana-Dashboard"                       │
├─────────────────────────────────────────────────────────────────┤
│  Ebene 3: Integrationstests                                     │
│  Zusammenspiel der Komponenten (Alloy → Mimir, Ruler → AM)     │
│  "Daten fließen korrekt durch die gesamte Pipeline"             │
├─────────────────────────────────────────────────────────────────┤
│  Ebene 2: Komponententests                                      │
│  Einzelne Komponente isoliert verifiziert                       │
│  "Mimir ist healthy, Grafana zeigt Datasources"                 │
├─────────────────────────────────────────────────────────────────┤
│  Ebene 1: Unit-Tests / Konfigurationstests                      │
│  Lokale Verifikation ohne laufenden Cluster                     │
│  "Rule-Expressions sind syntaktisch korrekt"                    │
└─────────────────────────────────────────────────────────────────┘
```

Jede Ebene baut auf der darunter auf. Ebene 1 läuft vor jedem Commit,
Ebene 4 nur nach vollständigem Deployment in Int.

---

## 2. Ebene 1: Unit-Tests / Konfigurationstests

**Wann:** Lokal vor jedem Commit, automatisierbar in CI  
**Tool:** `promtool`, `helm lint`, `yaml lint`  
**Cluster:** nicht benötigt

### 2.1 Mimir — Rule-Unit-Tests

Prometheus Alert-Expressions lokal gegen synthetische Zeitreihen testen:

```bash
# Installation: brew install prometheus (enthält promtool)

# Testdatei: apps/mimir/tests/test-pipeline-health.yaml
promtool test rules apps/mimir/tests/test-pipeline-health.yaml
# Erwartetes Ergebnis: "SUCCESS: 1 tests passed"
```

Beispiel-Testdatei `apps/mimir/tests/test-pipeline-health.yaml`:

```yaml
rule_files:
  - ../prod/files/mimir/alerts-pipeline-health.yaml

tests:
  - interval: 1m
    input_series:
      - series: 'cortex_distributor_received_samples_total{cluster="prod-bwcloud"}'
        values: '0 0 0 0 0 0'
    alert_rule_test:
      - eval_time: 6m
        alertname: AlloyIngestionStopped
        exp_alerts:
          - exp_labels:
              severity: critical
```

### 2.2 Helm-Konfigurationsvalidierung

```bash
helm lint apps/mimir/prod/
helm lint apps/grafana/prod/
helm lint apps/alloy/prod/

# ConfigMap-Aggregation korrekt?
helm template apps/mimir/prod/ | grep -A5 "mimir-rules-bundle"
```

---

## 3. Ebene 2: Komponententests

**Wann:** Nach jedem Deployment einer einzelnen Komponente  
**Tool:** `curl`, `kubectl`  
**Cluster:** erforderlich

### 3.1 Mimir

```bash
export MIMIR=https://mimir.saadisfy.me
export ORG=1

# Gateway erreichbar?
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/labels" \
  | jq -e '.status == "success"'

# Alle Komponenten healthy?
kubectl get pods -n mimir
# Erwartetes Ergebnis: alle Pods Running/Ready
# (distributor, ingester, querier, query-frontend, ruler,
#  alertmanager, compactor, store-gateway)

# Ingester im Ring?
curl -sf "$MIMIR/ingester/ring" | grep -c "ACTIVE"

# Ruler hat Rules geladen?
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/rules" \
  | jq '[.data.groups[].name]'

# Alertmanager erreichbar?
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/alertmanager/api/v2/status" \
  | jq '.cluster.status'
```

**Checkliste Mimir-Komponenten:**

| Check | Kommando | Erwartetes Ergebnis |
|---|---|---|
| Gateway erreichbar | `curl .../api/v1/labels` | HTTP 200, status=success |
| Alle Pods Ready | `kubectl get pods -n mimir` | 0 Pods nicht-Ready |
| Ingester im Ring | `curl .../ingester/ring` | ≥ 1 ACTIVE |
| Ruler lädt Rules | `curl .../api/v1/rules` | Alle Rule-Gruppen vorhanden |
| Blocks-Storage (PV) | `kubectl get pvc -n mimir` | Alle PVCs Bound |
| Alertmanager | `curl .../alertmanager/api/v2/status` | cluster.status = ready |

### 3.2 Alloy

```bash
# Alloy-Pods laufen?
kubectl get pods -n alloy

# Alloy meldet sich in Mimir (eigene Metriken vorhanden)?
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
  --data-urlencode 'query=alloy_build_info{cluster="prod-bwcloud"}' \
  | jq '.data.result[0].metric.version'
# Erwartetes Ergebnis: Versionstring

# Keine kritischen Fehler in Alloy-Logs?
kubectl logs -n alloy -l app.kubernetes.io/name=alloy --tail=50 \
  | grep -i "error|failed|panic" | grep -v "level=debug"

# Alloy-interne Queue nicht überfüllt?
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
  --data-urlencode 'query=otelcol_exporter_queue_size{cluster="prod-bwcloud"}' \
  | jq '.data.result[0].value[1]'
# Erwartetes Ergebnis: deutlich < queue_capacity
```

**Checkliste Alloy-Komponenten:**

| Check | Erwartetes Ergebnis |
|---|---|
| Pod Running/Ready | 1/1 |
| `alloy_build_info` in Mimir vorhanden | version-Label gesetzt |
| Keine ERROR-Logs | 0 Error-Lines in letzten 50 Log-Zeilen |
| Exporter-Queue nicht voll | < 80% der Kapazität |
| Memory Limiter nicht aktiv | `otelcol_processor_refused_metric_points` = 0 |

### 3.3 Grafana

```bash
# Grafana erreichbar?
curl -sf https://grafana.saadisfy.me/api/health | jq .

# Datasource "Mimir" vorhanden?
curl -sf -u admin:$GRAFANA_PASS https://grafana.saadisfy.me/api/datasources \
  | jq '[.[] | {name, type, url}]'

# Datasource-Health testen
curl -sf -u admin:$GRAFANA_PASS \
  "https://grafana.saadisfy.me/api/datasources/uid/<uid>/health" \
  | jq .status
# Erwartetes Ergebnis: "OK"

# Dashboards vorhanden?
curl -sf -u admin:$GRAFANA_PASS "https://grafana.saadisfy.me/api/search?type=dash-db" \
  | jq 'length'
# Erwartetes Ergebnis: > 0
```

**Checkliste Grafana-Komponenten:**

| Check | Erwartetes Ergebnis |
|---|---|
| `/api/health` | HTTP 200, database=ok |
| SSO-Redirect | OIDC-Login erscheint (manuell) |
| Datasource Mimir vorhanden | Typ `prometheus`, URL auf Mimir-Gateway |
| Datasource health | Status "OK" |
| Dashboards geladen | > 0 Dashboards |
| Alert-Tab erreichbar | Zeigt Rule-Gruppen aus Mimir |

---

## 4. Ebene 3: Integrationstests

**Wann:** Nach Änderungen die mehrere Komponenten betreffen  
**Tool:** `curl`, `kubectl`, `promtool`  
**Cluster:** erforderlich

### 4.1 Alloy → Mimir: Ingestion-Pfad

```bash
export MIMIR=https://mimir.saadisfy.me; export ORG=1
mquery() {
  curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
    --data-urlencode "query=$1" | jq -r '.data.result'
}

# Ingestion läuft?
mquery 'sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[2m]))'
# > 0

# Keine Samples verworfen?
mquery 'sum(rate(cortex_discarded_samples_total{cluster="prod-bwcloud"}[5m]))'
# = 0 oder kein Result
```

### 4.2 Alloy → Mimir: Label-Vollständigkeit pro Scrape-Target

```bash
check_labels() {
  local desc=$1 query=$2; shift 2; local labels=("$@")
  local result
  result=$(curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
    --data-urlencode "query=$query" | jq -r '.data.result[0].metric // empty')
  [[ -z $result ]] && { echo "❌ $desc: keine Daten"; return; }
  for label in "${labels[@]}"; do
    val=$(echo "$result" | jq -r ".\"$label\" // empty")
    [[ -z $val ]] && echo "❌ $desc: Label '$label' fehlt" \
                  || echo "✅ $desc: $label=$val"
  done
}

check_labels "cadvisor"           'container_cpu_usage_seconds_total{namespace="mimir"}' namespace pod container node cluster
check_labels "kube-state-metrics" 'kube_pod_info{namespace="mimir"}'                    namespace pod node cluster
check_labels "node-exporter"      'node_cpu_seconds_total'                               node cluster
check_labels "alloy"              'alloy_build_info'                                     cluster
check_labels "mimir"              'cortex_request_duration_seconds_sum{namespace="mimir"}' namespace cluster
```

### 4.3 Alloy → Mimir: Scrape-Coverage

```bash
declare -A CHECKS=(
  ["cadvisor"]='container_cpu_usage_seconds_total{cluster="prod-bwcloud"}'
  ["kubelet"]='kubelet_node_name{cluster="prod-bwcloud"}'
  ["kube-state-metrics"]='kube_pod_info{cluster="prod-bwcloud"}'
  ["node-exporter"]='node_cpu_seconds_total{cluster="prod-bwcloud"}'
  ["alloy-self"]='alloy_build_info{cluster="prod-bwcloud"}'
  ["mimir-self"]='cortex_request_duration_seconds_sum{cluster="prod-bwcloud"}'
)
for name in "${!CHECKS[@]}"; do
  count=$(curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
    --data-urlencode "query=${CHECKS[$name]}" | jq '.data.result | length')
  echo "$([[ $count -gt 0 ]] && echo ✅ || echo ❌)  $name ($count series)"
done
```

### 4.4 Mimir Ruler → Alertmanager (Smoke-Test)

Temporäre Rule deployen, die garantiert feuert:

```yaml
# apps/mimir/prod/files/mimir/alerts-smoketest.yaml
groups:
  - name: smoketest
    rules:
      - alert: RulerSmokeTest
        expr: vector(1) == 1
        for: 1m
        labels:
          severity: none
          test: "true"
```

```bash
git add . && git commit -m "test: ruler smoketest" && git push
# → warten ~90s bis Reloader Pod neu startet

# Alert muss erscheinen:
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/alerts" \
  | jq '[.data.alerts[] | select(.labels.alertname=="RulerSmokeTest")]'

# Aufräumen:
git rm apps/mimir/prod/files/mimir/alerts-smoketest.yaml
git commit -m "test: remove smoketest" && git push

# Ruler evaluiert ohne Fehler?
mquery 'sum(rate(cortex_ruler_evaluation_failures_total{cluster="prod-bwcloud"}[5m]))'
# = 0
```

### 4.5 Mimir → Grafana: Daten sichtbar über Datasource-Proxy

```bash
# Prüft den gesamten Proxy-Pfad inkl. Auth
curl -sf -u admin:$GRAFANA_PASS \
  "https://grafana.saadisfy.me/api/datasources/proxy/uid/<mimir-uid>/api/v1/query" \
  --data-urlencode 'query=up{cluster="prod-bwcloud"}' \
  | jq '.data.result | length'
# > 0
```

### 4.6 Config-Reload: Git-Push → Ruler lädt neue Rules

```bash
BEFORE=$(curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/rules" \
  | jq '.data.groups | length')
# → Neue Rule-Datei committen und pushen
kubectl rollout status deployment/mimir-ruler -n mimir --timeout=120s
AFTER=$(curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/rules" \
  | jq '.data.groups | length')
[[ $AFTER -gt $BEFORE ]] && echo "✅ Neue Rules geladen" || echo "❌ Keine Änderung"
```

---

## 5. Ebene 4: Blackbox E2E

**Wann:** Nach vollständigem Deployment in Int, vor UAT-Abnahme  
**Perspektive:** Endnutzer — kein internes Wissen über Implementierung  
**Tool:** Browser (manuell), `curl` gegen öffentliche Endpunkte

### 5.1 Metrik-Durchlauf (vollständige Pipeline)

```
Alloy scrapet Node-Exporter
  → Mimir nimmt Samples an
    → Grafana-Dashboard zeigt node_cpu_seconds_total
      → Alert "NodeExporterMetricsMissing" ist NICHT aktiv
```

**Schritte (manuell):**
1. Grafana öffnen: `https://grafana.saadisfy.me`
2. Explore → Datasource "Mimir" → Query: `node_cpu_seconds_total{cluster="prod-bwcloud"}`
3. Ergebnis: Zeitreihe sichtbar, Labels `node` und `cluster` vorhanden
4. Alerting → Alert rules → `NodeExporterMetricsMissing` = Normal (nicht feuern)

### 5.2 Login und Zugriffskontrolle (SSO)

**Schritte (manuell):**
1. Privates Browser-Fenster: `https://grafana.saadisfy.me`
2. Redirect auf OIDC-Provider erscheint → Login mit SSO-Account
3. Nach Login: Dashboard-Übersicht sichtbar
4. Logout → erneuter Aufruf → kein Zugriff ohne Auth

### 5.3 Alert-Lifecycle (vollständige Kette)

```
Rule feuert in Mimir Ruler
  → Alert erscheint in Alertmanager
    → Grafana Alert-Tab zeigt "Firing"
      → Notification an Receiver (Webhook/Slack) zugestellt
```

**Schritte:**
1. Smoke-Test-Rule deployen (siehe Szenario 4.4)
2. Nach ~2min: Grafana → Alerting → Alert rules → `RulerSmokeTest` = Firing
3. Alertmanager-API: `curl .../alertmanager/api/v2/alerts` → Alert aktiv
4. Webhook-Receiver (falls konfiguriert): Payload empfangen
5. Aufräumen: Rule-Datei entfernen und pushen

### 5.4 Dashboard-Vollständigkeit

**Schritte (manuell):**
1. Grafana → Dashboards
2. Alle erwarteten Dashboards vorhanden und öffnen ohne Fehler
3. Kein Panel zeigt dauerhaft "No data" bei laufendem Cluster
4. Variablen (Namespace, Pod) werden befüllt

---

## 6. Kontinuierliche Überwachung (Schicht 1 Alerts)

Diese Alerts laufen permanent im Cluster und alarmieren proaktiv:

### 6.1 Pipeline-Health

```yaml
groups:
  - name: mimir_pipeline_health
    rules:
      - alert: AlloyIngestionStopped
        expr: sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[5m])) == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Mimir empfängt keine Samples mehr"
          description: "Ingestion-Rate seit 5min = 0. Alloy oder Distributor ausgefallen."

      - alert: AlloyIngestionRateLow
        expr: sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[5m])) < 100
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Mimir Ingestion-Rate ungewöhnlich niedrig"

      - alert: MimirDistributorHighErrorRate
        expr: |
          sum(rate(cortex_discarded_samples_total{cluster="prod-bwcloud"}[5m]))
          / sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Mimir verwirft >5% der eingehenden Samples"

      - alert: AlloyScrapeMissing
        expr: absent(alloy_build_info{cluster="prod-bwcloud"})
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Alloy-Metriken fehlen in Mimir"
```

### 6.2 Scrape-Coverage

```yaml
groups:
  - name: mimir_scrape_coverage
    rules:
      - alert: KubeletMetricsMissing
        expr: absent(container_cpu_usage_seconds_total{cluster="prod-bwcloud"})
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Kubelet/cAdvisor Metriken fehlen"

      - alert: KubeStateMetricsMissing
        expr: absent(kube_pod_info{cluster="prod-bwcloud"})
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "kube-state-metrics Metriken fehlen"

      - alert: NodeExporterMetricsMissing
        expr: absent(node_cpu_seconds_total{cluster="prod-bwcloud"})
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Node Exporter Metriken fehlen"
```

### 6.3 Ruler-Self-Monitoring

```yaml
      - alert: MimirRulerNoRulesLoaded
        expr: sum(cortex_ruler_rules_configured{cluster="prod-bwcloud"}) == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Mimir Ruler hat keine Rules geladen"

      - alert: MimirRulerEvaluationFailing
        expr: sum(rate(cortex_ruler_evaluation_failures_total{cluster="prod-bwcloud"}[5m])) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Mimir Ruler: Rule-Evaluation schlägt fehl"
```

---

## 7. Performance-Tests

**Wann:** Int-Stage, vor UAT  
**Tools:** Offizielles k6-Skript aus `grafana/mimir` oder `mimirtool loadgen`

### 7.1 k6 (Write + Read Last)

```bash
# xk6 bauen
go install go.k6.io/xk6/cmd/xk6@latest
xk6 build --with github.com/grafana/xk6-client-prometheus-remote@latest

# Skript holen
curl -O https://raw.githubusercontent.com/grafana/mimir/main/operations/k6/load-testing-with-k6.js

# Smoke-Test (5 Minuten)
./k6 run load-testing-with-k6.js \
  -e K6_WRITE_HOSTNAME="mimir.saadisfy.me" \
  -e K6_READ_HOSTNAME="mimir.saadisfy.me" \
  -e K6_SCHEME="https" \
  -e K6_WRITE_TENANT_ID="1" \
  -e K6_READ_TENANT_ID="1" \
  -e K6_WRITE_REQUEST_RATE="1" \
  -e K6_WRITE_SERIES_PER_REQUEST="100" \
  -e K6_READ_REQUEST_RATE="1" \
  -e K6_DURATION_MIN="5"
```

SLA-Thresholds (im Skript eingebaut): 99.9% Writes succeed, avg Query-Latenz < 2s

### 7.2 mimirtool loadgen (Alternative, kein Build nötig)

```bash
mimirtool loadgen \
  --write-url=https://mimir.saadisfy.me/api/v1/push \
  --query-url=https://mimir.saadisfy.me/prometheus \
  --active-series=1000 \
  --scrape-interval=15s \
  --tenant-id=1
```

---

## 8. Zuordnung zu Stage

### Dev

| Ebene | Tests | Automatisierbar |
|---|---|---|
| 1 — Unit | `promtool test rules`, `helm lint` | ✅ CI/pre-commit |
| 2 — Komponente | Alle Pods Ready, Gateway erreichbar, Rules geladen | ✅ Script |
| 3 — Integration | Ingestion-Rate, Label-Checks, Scrape-Coverage | ✅ Script |
| Kontinuierlich | Schicht-1-Alerts laufen permanent | ✅ automatisch |

### Int / UAT

| Ebene | Tests | Automatisierbar |
|---|---|---|
| 1–3 | Alle Dev-Tests müssen bestehen | ✅ Voraussetzung |
| 4 — Blackbox E2E | Login/SSO, Dashboard-Vollständigkeit, Alert-Lifecycle | ⚠️ Manuell |
| Performance | k6-Last: Write-Fehlerrate < 0.1%, avg Query < 2s | ✅ k6 |
| Ressourcen | Kein OOMKill, kein CrashLoop nach 1h Dauerlast | ✅ Monitoring |

---

## 9. Artefakte und TODOs

| Artefakt | Speicherort | Status |
|---|---|---|
| Testkonzept | `docs/mimir-test-konzept.md` | ✅ |
| Ruler & Alerting Setup | `docs/mimir-ruler-alerting-setup.md` | ✅ |
| Pipeline-Health Alerts | `apps/mimir/prod/files/mimir/alerts-pipeline-health.yaml` | ⚠️ noch anlegen |
| Scrape-Coverage Alerts | `apps/mimir/prod/files/mimir/alerts-scrape-coverage.yaml` | ⚠️ noch anlegen |
| promtool Unit-Tests | `apps/mimir/tests/` | ⚠️ noch anlegen |

---

## 10. Akzeptanzkriterien

- [x] Testhierarchie (4 Ebenen) ist definiert
- [x] Tests sind pro Komponente aufgegliedert (Mimir, Alloy, Grafana)
- [x] Tools sind identifiziert und dokumentiert
- [x] Stage-Zuordnung (Dev vs. Int/UAT) ist definiert
- [x] Kontinuierliche Alerts (Schicht 1) sind spezifiziert
- [x] Performance-Tests referenzieren offizielle Tools
- [ ] Alert-Dateien anlegen (`alerts-pipeline-health.yaml`, `alerts-scrape-coverage.yaml`)
- [ ] promtool Unit-Tests anlegen (`apps/mimir/tests/`)
