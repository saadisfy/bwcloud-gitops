# Mimir Observability — Testkonzept

Dieses Dokument beschreibt das Testkonzept für die Mimir-basierte Observability-Plattform.
Es definiert Testarten, benötigte Tools, Datenversorgung, Stage-Zuordnung und Akzeptanzkriterien.

---

## 1. Testarten

### 1.1 Funktionale Tests

Prüfen ob die Kernfunktionen der Observability-Pipeline korrekt arbeiten.

**Unterarten:**

| Testart | Beschreibung | Beispiele |
|---|---|---|
| **Ingestion-Tests** | Metriken kommen vollständig und korrekt in Mimir an | Ingestion-Rate > 0, keine Samples verworfen |
| **Label-Vollständigkeit** | Erwartete Labels pro Scrape-Target sind gesetzt | `namespace`, `pod`, `cluster` auf cadvisor-Metriken |
| **Scrape-Coverage** | Alle definierten Scrape-Targets liefern Daten | Signatur-Metrik pro Target > 0 series |
| **Alert-Evaluation** | Ruler lädt Rules und evaluiert korrekt | Rules-API liefert alle Gruppen, keine Eval-Fehler |
| **Config-Reload** | Änderungen in Git landen nach Push im Ruler | Rule-Group-Count steigt nach Reloader-Restart |
| **Alertmanager-Routing** | Gefeuerte Alerts erreichen den Alertmanager | Smoke-Test-Alert erscheint in `/api/v1/alerts` |

### 1.2 Performance-Tests

Prüfen ob die Plattform unter Last stabil bleibt und Schwellwerte nicht überschritten werden.

**Tool: Offizielles Mimir k6-Skript** — Grafana pflegt in ihrem eigenen Repository ein vollständiges
Load-Test-Skript speziell für Mimir: [`operations/k6/load-testing-with-k6.js`](https://github.com/grafana/mimir/blob/main/operations/k6/load-testing-with-k6.js).
Kein eigenes Skript schreiben nötig.

Das Skript deckt bereits ab:
- **Write-Path**: Remote-Write mit konfigurierbarer Series-Anzahl, Scrape-Intervall, HA-Replikation
- **Read-Path**: Range Queries und Instant Queries mit realistischer Kardinalitätsverteilung (low/high)
- **Thresholds**: SLA-Checks eingebaut (99.9% writes succeed, avg query < 2s, 99.9% reads succeed)

**Pre-requisites:**

```bash
# xk6 installieren (k6 Build-Tool für Extensions)
go install go.k6.io/xk6/cmd/xk6@latest

# k6 mit Prometheus Remote-Write Extension bauen
xk6 build --with github.com/grafana/xk6-client-prometheus-remote@latest
```

**Kleiner Smoke-Test gegen das Setup:**

```bash
# Skript aus dem Mimir-Repo holen
curl -O https://raw.githubusercontent.com/grafana/mimir/main/operations/k6/load-testing-with-k6.js

# Kleiner Test: 1 Write-Request/s, 1 Read-Request/s, 5 Minuten
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

**Relevante Env-Variablen des Skripts:**

| Variable | Default | Beschreibung |
|---|---|---|
| `K6_WRITE_HOSTNAME` | — | Mimir Write-Pfad (Gateway/Distributor) |
| `K6_READ_HOSTNAME` | — | Mimir Read-Pfad (Query-Frontend) |
| `K6_WRITE_REQUEST_RATE` | 1 | Remote-Write Requests/Scrape-Intervall |
| `K6_WRITE_SERIES_PER_REQUEST` | 1000 | Series pro Request |
| `K6_READ_REQUEST_RATE` | 1 | Queries/s |
| `K6_DURATION_MIN` | 720 | Testdauer in Minuten |
| `K6_WRITE_TENANT_ID` | '' | X-Scope-OrgID für Writes |
| `K6_READ_TENANT_ID` | '' | X-Scope-OrgID für Reads |

### 1.3 Ressourcentests

Prüfen ob Pods innerhalb ihrer definierten Limits laufen und keine Memory-Leaks oder CPU-Spikes auftreten.

Gemessen via Mimir-eigene Metriken (kein externes Tool nötig):

```bash
export MIMIR=https://mimir.saadisfy.me; export ORG=1

# Memory-Auslastung pro Mimir-Komponente (% des Limits)
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
  --data-urlencode 'query=
    container_memory_working_set_bytes{namespace="mimir"}
    / on(pod, container)
    kube_pod_container_resource_limits{namespace="mimir", resource="memory"}
  ' | jq -r '.data.result[] | "\(.metric.container): \((.value[1] | tonumber * 100 | round))%"'

# CPU-Throttling (> 25% = Limit zu knapp)
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
  --data-urlencode 'query=
    rate(container_cpu_cfs_throttled_seconds_total{namespace="mimir"}[5m])
    / rate(container_cpu_cfs_periods_total{namespace="mimir"}[5m]) > 0.25
  ' | jq -r '.data.result[] | "\(.metric.container): \(.value[1])"'
```

---

## 2. Testdaten, Tools und Anbindungen

### 2.1 Testdaten

| Datenquelle | Beschreibung | Verfügbar in |
|---|---|---|
| **Live-Cluster-Metriken** | Echter Scrape via Alloy (cadvisor, kubelet, KSM, node-exporter) | Dev, Int |
| **Synthetische Metriken** | Via `k6 xk6-remote-write` generiert — definierte Kardinalität, Labels | Dev, Int |
| **Historische Metriken** | Aus Mimir-Blocks (PV) für Query-Tests | Int |
| **Smoke-Test-Alert** | `vector(1) == 1` Rule — feuert garantiert, zeitlich begrenzt einsetzen | Dev, Int |

### 2.2 Tools

| Tool | Zweck | Installation |
|---|---|---|
| `curl` + `jq` | Funktionale E2E-Tests gegen Mimir-API | Überall vorhanden |
| `promtool` | Lokale Rule-Unit-Tests (ohne Cluster) | `brew install prometheus` |
| `k6` + offizielles Mimir-Skript | Performance-/Lasttests (Write + Read Path) | `go install go.k6.io/xk6/cmd/xk6@latest` + `xk6 build --with github.com/grafana/xk6-client-prometheus-remote@latest` |
| `kubectl` | Pod-Status, Rollout-Verifikation, Logs | Cluster-Zugriff nötig |
| Grafana UI | Visuelle Verifikation von Dashboards und Alert-States | `https://grafana.saadisfy.me` |
| Mimir Prometheus API | Programmatische Abfragen, Rules/Alerts-Endpunkte | `https://mimir.saadisfy.me/prometheus` |

### 2.3 Anbindungen

```
Test-Maschine (lokal / CI)
  │
  ├── curl/k6 → https://mimir.saadisfy.me     (Gateway, Ingestion + Query)
  ├── kubectl  → noctua-k3s                    (Pod-Status, Logs)
  └── Grafana  → https://grafana.saadisfy.me   (visuelle Verifikation)

Mimir-intern:
  Alloy (DaemonSet) → Distributor:8080 (OTLP/HTTP) → Ingester → Ruler ← ConfigMap-Mount
```

---

## 3. Datenversorgung für Observability Dev & Int

### Dev-Stage

- **Quelle:** Live-Metriken vom `noctua-k3s`-Cluster via Alloy
- **Umfang:** Alle definierten Scrape-Targets (cadvisor, kubelet, KSM, node-exporter, Alloy-self, Mimir-self)
- **Tenant:** `1` (einziger Tenant)
- **Retention:** 24h (Compactor-Einstellung in `base/values.yaml`)
- **Synthetische Daten:** können jederzeit via k6 oder curl remote-write gepusht werden

### Int-Stage

- **Quelle:** identisch zu Dev (gleicher Cluster), ggf. separater Namespace oder Tenant
- **Zusatz:** historische Daten aus vorherigen Test-Runs für Query-Lasttests nutzbar
- **UAT-Anforderung:** Reale Produktions-ähnliche Last, kein synthetischer Traffic allein

> **Offen:** Separater Mimir-Tenant oder separater Namespace für Int noch nicht definiert.
> Aktuell läuft alles unter Tenant `1`. Für echte Stage-Trennung: eigener Tenant (z.B. `2`) oder
> separate Mimir-Instanz empfohlen.

---

## 4. Setup und Umgebungsaufbau

### 4.1 Voraussetzungen

```bash
# 1. Cluster-Zugriff prüfen
kubectl get pods -n mimir

# 2. Mimir Gateway erreichbar
curl -sf -H "X-Scope-OrgID: 1" https://mimir.saadisfy.me/prometheus/api/v1/labels | jq .status

# 3. Tools installieren
brew install prometheus   # enthält promtool
brew install k6
brew install jq
```

### 4.2 Basis-Umgebungsvariablen (für alle Tests)

```bash
export MIMIR=https://mimir.saadisfy.me
export ORG=1

# Hilfsfunktion für schnelle PromQL-Abfragen
mquery() {
  curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
    --data-urlencode "query=$1" | jq -r '.data.result'
}
```

### 4.3 Mimir Ruler-Konfiguration verifizieren (vor Teststart)

```bash
# Rules geladen?
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/rules" \
  | jq '[.data.groups[] | .name]'

# Ruler-Pod läuft?
kubectl get pods -n mimir -l app.kubernetes.io/component=ruler

# ConfigMap korrekt befüllt?
kubectl get configmap mimir-rules-bundle -n mimir -o jsonpath='{.data.rules\.yaml}' | head -20
```

---

## 5. Zusätzliche Tools

| Tool | Notwendig für | Bewertung |
|---|---|---|
| **k6 + offizielles Mimir-Skript** | Performance-Tests (Ingestion-Last, Query-Last) | ✅ empfohlen — kein eigenes Skript schreiben |
| **Testcustomer-App** | Realistische Applikations-Metriken (statt synthetischer Daten) | ⚠️ optional, erhöht Realismus in Int |
| **Lasttreiber (allgemein)** | CPU/RAM-Last auf Nodes erzeugen um Ressourcen-Alerts zu triggern | ⚠️ optional für Ressourcentests |
| **Alertmanager Webhook-Receiver** | Verifikation dass Alerts tatsächlich zugestellt werden | ✅ empfohlen für Int-UAT |

**Alertmanager Webhook-Receiver für Tests** (einfachste Option):

```bash
# Temporären Webhook-Listener starten (empfängt alle gefeuerten Alerts)
kubectl run webhook-test --image=mendhak/http-https-echo -n mimir \
  --port=8080 --expose

# In Alertmanager-Config eintragen:
# receivers:
#   - name: webhook-test
#     webhook_configs:
#       - url: http://webhook-test.mimir.svc.cluster.local:8080
```

---

## 6. Zuordnung von Tests zur Stage

### 6.1 Dev — Was wird hier getestet?

Fokus: **Funktionalität und Konfigurationskorrektheit**

| Test | Testart | Tool | Automatisierbar? |
|---|---|---|---|
| Alert-Expressions syntaktisch korrekt | Funktional (Unit) | `promtool test rules` | ✅ Ja (pre-commit / CI) |
| Ingestion-Pfad E2E | Funktional | `curl` | ✅ Ja |
| Label-Vollständigkeit pro Scrape-Target | Funktional | `curl` + `jq` | ✅ Ja |
| Alle Scrape-Quellen aktiv | Funktional | `curl`-Schleife | ✅ Ja |
| Ruler lädt Rules nach Git-Push | Funktional | `curl` + `kubectl` | ⚠️ Semi (manuell triggern) |
| Ruler-Smoke-Test (vector(1)==1) | Funktional | Git-Commit + `curl` | ⚠️ Manuell |
| Memory/CPU innerhalb Limits | Ressource | `curl` (Mimir-Metriken) | ✅ Ja |

**Kontinuierliche Überwachung in Dev (Schicht 1 Alerts):**
- `AlloyIngestionStopped` — Ingestion vollständig ausgefallen
- `AlloyIngestionRateLow` — Rate unter Schwellwert
- `MimirDistributorHighErrorRate` — Samples werden verworfen
- `AlloyScrapeMissing` — Alloy meldet sich nicht mehr
- `KubeletMetricsMissing`, `KubeStateMetricsMissing`, `NodeExporterMetricsMissing`
- `MimirRulerNoRulesLoaded`, `MimirRulerEvaluationFailing`

### 6.2 Int — Was wird im Rahmen des UATs getestet?

Fokus: **Akzeptanz, Last, End-to-End-Realismus**

| Test | Testart | Tool | Kriterium |
|---|---|---|---|
| Alle Dev-Tests bestanden | Funktional | siehe Dev | Voraussetzung |
| Query-Latenz unter Last | Performance | k6 | P99 < 2s bei 20 parallelen Queries |
| Ingestion-Stabilität unter Last | Performance | k6 + offizielles Mimir-Skript | Fehlerrate < 0.1% bei 10k samples/s |
| Cardinality-Limit greift korrekt | Performance/Funktional | k6 | HTTP 429 bei Überschreitung |
| Alerts erscheinen in Grafana UI | Funktional (UAT) | Grafana UI | Manuell: Alert-Tab zeigt aktive Alerts |
| Alert wird an Alertmanager zugestellt | Funktional (UAT) | Webhook-Receiver | Manuell: Webhook empfängt Payload |
| Dashboard zeigt Realdaten korrekt | Funktional (UAT) | Grafana UI | Manuell: Panels ohne `No data` |
| Ressourcen stabil nach 1h Dauerlast | Ressource | `curl` + k6 | Kein OOMKill, kein CrashLoop |

---

## 7. Artefakte und Dokumente

| Artefakt | Speicherort | Status |
|---|---|---|
| Testkonzept (dieses Dokument) | `docs/mimir-test-konzept.md` | ✅ vorhanden |
| Ruler & Alerting Setup Dokumentation | `docs/mimir-ruler-alerting-setup.md` | ✅ vorhanden |
| Alert-Rules (Schicht 1) | `apps/mimir/prod/files/mimir/alerts-*.yaml` | ✅ vorhanden |
| Scrape-Coverage Alerts | `apps/mimir/prod/files/mimir/alerts-scrape-coverage.yaml` | ⚠️ noch anlegen |
| Pipeline-Health Alerts | `apps/mimir/prod/files/mimir/alerts-pipeline-health.yaml` | ⚠️ noch anlegen |
| promtool Unit-Test Dateien | `apps/mimir/tests/` | ⚠️ noch anlegen |
| k6 Performance-Test Skript | `operations/k6/` im [grafana/mimir](https://github.com/grafana/mimir/blob/main/operations/k6/load-testing-with-k6.js) Repo | ✅ vorhanden (extern) |
| Test-Setup Schaubild | — | 📋 TODO |

---

## 8. Akzeptanzkriterien

- [x] Testarten sind definiert (Funktional, Performance, Ressourcen)
- [x] Benötigte Tools sind identifiziert und dokumentiert
- [x] Datenversorgung für Dev und Int ist beschrieben
- [x] Setup und Umgebungsaufbau ist dokumentiert
- [x] Tests sind den Stages zugeordnet (Dev vs. Int/UAT)
- [x] Artefakte/Dokumente sind aufgelistet
- [ ] **TODO: Schaubild zum Test-Setup** — zeigt Datenfluss von Testdaten über Alloy/k6 in Mimir, Query-Pfad zurück zu curl/Grafana, und Alert-Pfad zu Alertmanager
- [ ] Scrape-Coverage und Pipeline-Health Alert-Dateien anlegen (`apps/mimir/prod/files/mimir/`)
- [ ] promtool Unit-Tests anlegen (`apps/mimir/tests/`)
- [ ] k6-Skripte anlegen (`apps/mimir/tests/k6/`)

---

## Anhang: Funktionale E2E-Szenarien (Referenz-Kommandos)

### Setup

```bash
export MIMIR=https://mimir.saadisfy.me
export ORG=1
mquery() {
  curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
    --data-urlencode "query=$1" | jq -r '.data.result'
}
```

### A: Ingestion-Pfad

```bash
mquery 'sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[2m]))'
mquery 'sum(rate(cortex_discarded_samples_total{cluster="prod-bwcloud"}[5m]))'
mquery 'alloy_build_info{cluster="prod-bwcloud"}'
```

### B: Label-Vollständigkeit pro Scrape-Target

```bash
check_labels() {
  local desc=$1; local query=$2; shift 2; local labels=("$@")
  local result=$(curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
    --data-urlencode "query=$query" | jq -r '.data.result[0].metric // empty')
  if [[ -z $result ]]; then echo "❌ $desc: keine Daten"; return; fi
  for label in "${labels[@]}"; do
    val=$(echo $result | jq -r ".\"$label\" // empty")
    [[ -z $val ]] && echo "❌ $desc: Label '$label' fehlt" || echo "✅ $desc: $label=$val"
  done
}
check_labels "cadvisor"           'container_cpu_usage_seconds_total{namespace="mimir"}' namespace pod container node cluster
check_labels "kube-state-metrics" 'kube_pod_info{namespace="mimir"}'                    namespace pod node cluster
check_labels "node-exporter"      'node_cpu_seconds_total'                               node cluster
check_labels "alloy"              'alloy_build_info'                                     cluster
check_labels "mimir"              'cortex_request_duration_seconds_sum{namespace="mimir"}' namespace cluster
```

### C: Scrape-Coverage

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

### D: Metrik-Volumen

```bash
mquery 'sum(cortex_ingester_memory_series{cluster="prod-bwcloud"})'
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
  --data-urlencode 'query=topk(10, count by (namespace) ({namespace!="", cluster="prod-bwcloud"}))' \
  | jq -r '.data.result[] | "\(.metric.namespace): \(.value[1])"' | sort -t: -k2 -rn
```

### E: Ruler Smoke-Test

```bash
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/rules" \
  | jq '[.data.groups[] | {group: .name, rules: [.rules[].name]}]'
curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/alerts" \
  | jq '[.data.alerts[] | select(.state=="firing") | {alert: .labels.alertname, severity: .labels.severity}]'
```

### F: Rule Unit-Tests (lokal)

```bash
promtool test rules /path/to/apps/mimir/tests/<test-file>.yaml
```

### G: Config-Reload verifizieren

```bash
BEFORE=$(curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/rules" | jq '.data.groups | length')
# → committen & pushen
kubectl rollout status deployment/mimir-ruler -n mimir --timeout=120s
AFTER=$(curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/rules" | jq '.data.groups | length')
[[ $AFTER -gt $BEFORE ]] && echo "✅ Neue Rules geladen" || echo "❌ Keine Änderung"
```


```
┌─────────────────────────────────────────────────────────┐
│  Schicht 1: Kontinuierliche Alerts (immer aktiv)        │
│  → Mimir-Ruler bewertet permanent, feuert bei Abweichung│
│  → Niemand muss aktiv nachschauen                       │
├─────────────────────────────────────────────────────────┤
│  Schicht 2: E2E-Szenarien (manuell / nach Änderungen)   │
│  → Gezielt ausgeführt nach Konfigurationsänderungen     │
│  → Verifiziert Datenfluss, Labels, Vollständigkeit      │
└─────────────────────────────────────────────────────────┘
```

---

## Schicht 1: Kontinuierliche Alerts

Die folgenden Alerts decken die kritischen Punkte der Pipeline
`Alloy → Mimir Distributor → Ingester → Ruler` ab.

### 1.1 Ingestion-Pipeline

**Datei:** `apps/mimir/prod/files/mimir/alerts-pipeline-health.yaml`

```yaml
groups:
  - name: mimir_pipeline_health
    rules:

      # Alloy sendet keine Metriken mehr an Mimir
      - alert: AlloyIngestionStopped
        expr: |
          sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[5m])) == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Mimir empfängt keine Samples mehr"
          description: "Die Ingestion-Rate ist seit 5 Minuten 0. Alloy oder der Distributor ist ausgefallen."

      # Ingestion-Rate fällt unter einen Mindestschwellwert
      # Schwellwert anpassen: normales Minimum aus Grafana ablesen
      - alert: AlloyIngestionRateLow
        expr: |
          sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[5m])) < 100
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Mimir Ingestion-Rate ungewöhnlich niedrig"
          description: "Weniger als 100 Samples/s über 10 Minuten. Erwartet: >> 100/s bei normalem Betrieb."

      # Distributor lehnt Samples ab (z.B. wegen Limits oder falscher OrgID)
      - alert: MimirDistributorHighErrorRate
        expr: |
          sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[5m])) > 0
          and
          (
            sum(rate(cortex_discarded_samples_total{cluster="prod-bwcloud"}[5m]))
            /
            sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[5m]))
          ) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Mimir verwirft >5% der eingehenden Samples"
          description: "Mögliche Ursache: Limit überschritten, falsche OrgID, oder Label-Validierungsfehler."

      # Alloy selbst meldet sich nicht mehr (eigene Metriken fehlen)
      - alert: AlloyScrapeMissing
        expr: |
          absent(alloy_build_info{cluster="prod-bwcloud"})
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Alloy-Metriken fehlen in Mimir"
          description: "alloy_build_info ist nicht vorhanden. Alloy scrapet sich nicht mehr selbst oder sendet nicht an Mimir."
```

### 1.2 Scrape-Target-Vollständigkeit

Diese Alerts stellen sicher, dass alle erwarteten Scrape-Quellen aktiv bleiben:

**Datei:** `apps/mimir/prod/files/mimir/alerts-scrape-coverage.yaml`

```yaml
groups:
  - name: mimir_scrape_coverage
    rules:

      # Kubelet-Metriken fehlen (cadvisor/kubelet scrape ausgefallen)
      - alert: KubeletMetricsMissing
        expr: |
          absent(container_cpu_usage_seconds_total{cluster="prod-bwcloud"})
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Kubelet/cAdvisor Metriken fehlen"
          description: "container_cpu_usage_seconds_total nicht vorhanden. Kubelet- oder cAdvisor-Scrape in Alloy ausgefallen."

      # Kube-State-Metrics fehlen
      - alert: KubeStateMetricsMissing
        expr: |
          absent(kube_pod_info{cluster="prod-bwcloud"})
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "kube-state-metrics Metriken fehlen"
          description: "kube_pod_info nicht vorhanden. kube-state-metrics scrape in Alloy ausgefallen."

      # Node Exporter Metriken fehlen
      - alert: NodeExporterMetricsMissing
        expr: |
          absent(node_cpu_seconds_total{cluster="prod-bwcloud"})
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Node Exporter Metriken fehlen"
          description: "node_cpu_seconds_total nicht vorhanden. Node-Exporter-Scrape ausgefallen."
```

### 1.3 Ruler selbst überwachen

```yaml
# In bestehende alerts-custom.yaml oder eigene Datei ergänzen
- alert: MimirRulerEvaluationFailing
  expr: |
    sum(rate(cortex_ruler_evaluation_failures_total{cluster="prod-bwcloud"}[5m])) > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Mimir Ruler: Rule-Evaluation schlägt fehl"
    description: "{{ $value }} Evaluierungsfehler/s. Rules können eventuell nicht korrekt feuern."

- alert: MimirRulerNoRulesLoaded
  expr: |
    sum(cortex_ruler_rules_configured{cluster="prod-bwcloud"}) == 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Mimir Ruler hat keine Rules geladen"
    description: "0 konfigurierte Rules. ConfigMap-Mount oder ruler_storage-Konfiguration ist fehlerhaft."
```

---

## Schicht 2: End-to-End-Szenarien

Diese Szenarien werden manuell ausgeführt — nach Konfigurationsänderungen, nach
Cluster-Updates oder als regelmäßiger Smoke-Test.

> **Hinweis zu Tools:** `grafana cli` ist ausschließlich für Plugin-Management und
> ist hier nicht geeignet. Die Szenarien nutzen stattdessen:
> - **`curl`** — direkt gegen Mimir's Prometheus-kompatible HTTP-API (keine Abhängigkeiten)
> - **`promtool`** — für lokales Rule-Unit-Testing ohne laufenden Cluster
> - **`mimirtool`** — optional, wo es wirklich kürzer ist (Rules list, Alertmanager get)

**Basis-Setup:**

```bash
export MIMIR=https://mimir.saadisfy.me
export ORG=1   # Tenant-ID

# Hilfsfunktion: PromQL-Query gegen Mimir
mquery() {
  curl -sf \
    -H "X-Scope-OrgID: $ORG" \
    "$MIMIR/prometheus/api/v1/query" \
    --data-urlencode "query=$1" \
    | jq -r '.data.result'
}
```

---

### Szenario A: Ingestion-Pfad funktioniert

Prüft: Daten kommen von Alloy an und sind sofort abfragbar.

```bash
# 1. Aktuelle Ingestion-Rate abfragen (muss > 0 sein)
mquery 'sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[2m]))'
# Erwartetes Ergebnis: ein Wert > 0

# 2. Prüfen ob Samples verworfen werden (muss 0 sein)
mquery 'sum(rate(cortex_discarded_samples_total{cluster="prod-bwcloud"}[5m]))'
# Erwartetes Ergebnis: 0 oder kein Result

# 3. Alloy meldet sich selbst
mquery 'alloy_build_info{cluster="prod-bwcloud"}'
# Erwartetes Ergebnis: mind. 1 Series mit version-Label
```

---

### Szenario B: Label-Vollständigkeit pro Scrape-Target

Prüft einmalig pro Scrape-Quelle ob die erwarteten Labels gesetzt sind.
Jede Quelle hat andere Labels — deswegen wird jede separat geprüft.

```bash
# Hilfsfunktion: prüft ob alle expected_labels in mindestens einem Result vorhanden sind
check_labels() {
  local desc=$1; local query=$2; shift 2; local labels=("$@")
  local result=$(curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/query" \
    --data-urlencode "query=$query" | jq -r '.data.result[0].metric // empty')
  if [[ -z $result ]]; then echo "❌ $desc: keine Daten"; return; fi
  for label in "${labels[@]}"; do
    val=$(echo $result | jq -r ".\"$label\" // empty")
    [[ -z $val ]] && echo "❌ $desc: Label '$label' fehlt" || echo "✅ $desc: $label=$val"
  done
}

# cadvisor (kubelet scrape) — muss k8s-Attribute-Enrichment durchlaufen
check_labels "cadvisor" \
  'container_cpu_usage_seconds_total{namespace="mimir"}' \
  namespace pod container node cluster

# kube-state-metrics — keine Pod-IP, kein k8sattributes; muss cluster-Label haben
check_labels "kube-state-metrics" \
  'kube_pod_info{namespace="mimir"}' \
  namespace pod node cluster

# node-exporter — kein namespace/pod, aber node und cluster müssen da sein
check_labels "node-exporter" \
  'node_cpu_seconds_total' \
  node cluster

# alloy self-scrape — cluster muss gesetzt sein
check_labels "alloy" \
  'alloy_build_info' \
  cluster

# mimir self-scrape — namespace und cluster
check_labels "mimir" \
  'cortex_request_duration_seconds_sum{namespace="mimir"}' \
  namespace cluster
```

**Wann ausführen:** Nach jeder Änderung an der Alloy-Pipeline (`config.alloy`), nach Cluster-Updates oder wenn Grafana-Dashboards plötzlich keine Daten mehr zeigen.

---

### Szenario C: Scrape-Target-Vollständigkeit

Prüft: Alle erwarteten Scrape-Quellen liefern Metriken.

```bash
# Alle Signature-Metriken in einer Schleife prüfen
declare -A CHECKS=(
  ["cadvisor"]='container_cpu_usage_seconds_total{cluster="prod-bwcloud"}'
  ["kubelet"]='kubelet_node_name{cluster="prod-bwcloud"}'
  ["kube-state-metrics"]='kube_pod_info{cluster="prod-bwcloud"}'
  ["node-exporter"]='node_cpu_seconds_total{cluster="prod-bwcloud"}'
  ["alloy-self"]='alloy_build_info{cluster="prod-bwcloud"}'
  ["mimir-self"]='cortex_request_duration_seconds_sum{cluster="prod-bwcloud"}'
)

for name in "${!CHECKS[@]}"; do
  count=$(curl -sf \
    -H "X-Scope-OrgID: $ORG" \
    "$MIMIR/prometheus/api/v1/query" \
    --data-urlencode "query=${CHECKS[$name]}" \
    | jq '.data.result | length')
  status=$([[ $count -gt 0 ]] && echo "✅" || echo "❌ FEHLT")
  echo "$status  $name ($count series)"
done
```

---

### Szenario D: Metrik-Volumen plausibel

Prüft: Series-Anzahl liegt in einem vernünftigen Bereich.

```bash
# Gesamt-Series für Tenant 1
mquery 'sum(cortex_ingester_memory_series{cluster="prod-bwcloud"})'

# Top-10 Namespaces nach Series-Anzahl
curl -sf \
  -H "X-Scope-OrgID: $ORG" \
  "$MIMIR/prometheus/api/v1/query" \
  --data-urlencode 'query=topk(10, count by (namespace) ({namespace!="", cluster="prod-bwcloud"}))' \
  | jq -r '.data.result[] | "\(.metric.namespace): \(.value[1])"' \
  | sort -t: -k2 -rn
```

---

### Szenario E: Alert-Evaluation funktioniert (Ruler Smoke-Test)

Prüft: Der Ruler lädt Rules, evaluiert sie korrekt.

```bash
# 1. Geladene Rules über Prometheus API abfragen (kein mimirtool nötig)
curl -sf \
  -H "X-Scope-OrgID: $ORG" \
  "$MIMIR/prometheus/api/v1/rules" \
  | jq '[.data.groups[] | {group: .name, rules: [.rules[].name]}]'
# Erwartetes Ergebnis: kubernetes-apps, mimir_alerts, mimir_custom_alerts usw. sichtbar

# 2. Aktuell feuernde Alerts
curl -sf \
  -H "X-Scope-OrgID: $ORG" \
  "$MIMIR/prometheus/api/v1/alerts" \
  | jq '[.data.alerts[] | select(.state=="firing") | {alert: .labels.alertname, severity: .labels.severity}]'

# 3. Ruler-Evaluation-Fehler prüfen (sollte 0 sein)
mquery 'sum(rate(cortex_ruler_evaluation_failures_total{cluster="prod-bwcloud"}[5m]))'
```

**Optional: Smoke-Test-Alert der garantiert feuert**

```bash
# Temporäre Datei anlegen, committen, nach Verifikation wieder löschen
cat > apps/mimir/prod/files/mimir/alerts-smoketest.yaml <<'EOF'
groups:
  - name: smoketest
    rules:
      - alert: RulerSmokeTest
        expr: vector(1) == 1
        for: 1m
        labels:
          severity: none
          test: "true"
        annotations:
          summary: "Ruler Smoke-Test — nach Verifikation löschen"
EOF
# → committen → warten bis Reloader neustarts → Alert in Schritt 2 sichtbar?
# → danach: git rm apps/mimir/prod/files/mimir/alerts-smoketest.yaml && git commit && git push
```

---

### Szenario F: Rule-Unit-Tests lokal (ohne Cluster)

Prüft: Alert-Expressions sind syntaktisch korrekt und feuern bei den richtigen Werten.
Dafür wird `promtool` verwendet — kein laufender Cluster nötig.

```bash
# promtool ist Teil des Prometheus-Binaries
# Installation: brew install prometheus  (oder direkt von https://github.com/prometheus/prometheus/releases)

# Unit-Test Datei anlegen:
cat > /tmp/test-mimir-alerts.yaml <<'EOF'
rule_files:
  - /path/to/apps/mimir/prod/files/mimir/alerts-custom.yaml

tests:
  - interval: 1m
    input_series:
      - series: 'cortex_ingester_flush_queues_length{namespace="mimir", pod="ingester-0"}'
        values: '0 0 0 0 6000 6000 6000 6000 6000 6000'  # steigt nach 4min über 5000

    alert_rule_test:
      - eval_time: 9m
        alertname: MimirIngesterFlushQueueHigh
        exp_alerts:
          - exp_labels:
              severity: warning
              namespace: mimir
              pod: ingester-0
            exp_annotations:
              message: "Mimir Ingester ingester-0 has 6000 series waiting..."
EOF

promtool test rules /tmp/test-mimir-alerts.yaml
# Erwartetes Ergebnis: "SUCCESS: 1 tests passed"
```

---

### Szenario G: Mimir Ruler Config-Reload verifizieren

Prüft: Nach einem Git-Push landen neue Rules tatsächlich im Ruler.

```bash
# Vor Änderung: Anzahl Rule-Groups merken
BEFORE=$(curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/rules" \
  | jq '.data.groups | length')

echo "Vor Änderung: $BEFORE Rule-Groups"

# → Neue Rule-Datei committen und pushen

# Warten bis Reloader den Pod neu gestartet hat
kubectl rollout status deployment/mimir-ruler -n mimir --timeout=120s

# Nach Restart prüfen
AFTER=$(curl -sf -H "X-Scope-OrgID: $ORG" "$MIMIR/prometheus/api/v1/rules" \
  | jq '.data.groups | length')

echo "Nach Änderung: $AFTER Rule-Groups"
[[ $AFTER -gt $BEFORE ]] && echo "✅ Neue Rules geladen" || echo "❌ Keine Änderung erkannt"
```

---

## Zusammenfassung: Was wird getestet

| Was | Wie | Wann |
|---|---|---|
| Ingestion läuft | Alert `AlloyIngestionStopped` | Kontinuierlich |
| Ingestion-Rate plausibel | Alert `AlloyIngestionRateLow` | Kontinuierlich |
| Samples werden nicht verworfen | Alert `MimirDistributorHighErrorRate` | Kontinuierlich |
| Alloy meldet sich selbst | Alert `AlloyScrapeMissing` | Kontinuierlich |
| Scrape-Targets vollständig | Alerts `*MetricsMissing` | Kontinuierlich |
| k8s-Labels vorhanden | Alerts `*MissingLabel` | Kontinuierlich |
| Ruler hat Rules geladen | Alert `MimirRulerNoRulesLoaded` | Kontinuierlich |
| Ruler evaluiert fehlerfrei | Alert `MimirRulerEvaluationFailing` | Kontinuierlich |
| Ingestion Pfad E2E | Szenario A (curl) | Nach Änderungen |
| Label-Vollständigkeit pro Scrape-Target | Szenario B (curl, einmalig) | Nach Alloy-Änderungen |
| Alle Scrape-Quellen aktiv | Szenario C (curl-Schleife) | Nach Alloy-Änderungen |
| Metrik-Volumen plausibel | Szenario D (curl) | Nach Cluster-Events |
| Ruler feuert Alerts | Szenario E (curl Prometheus API) | Nach Ruler-Konfigurationsänderungen |
| Rule-Expressions korrekt | Szenario F (promtool) | Lokal, vor jedem Commit |
| Config-Reload funktioniert | Szenario G (curl + kubectl) | Nach Rule-Änderungen |
