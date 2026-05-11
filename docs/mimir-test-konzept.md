# Mimir Konfigurationstest-Konzept

Dieses Dokument beschreibt, wie die Korrektheit der Mimir-Konfiguration kontinuierlich
überwacht und gezielt verifiziert wird — sowohl durch dauerhaft aktive Alerts als auch
durch manuelle End-to-End-Szenarien.

---

## Zwei Schichten

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

### 1.3 Label-Integrität

Fehlende Labels sind schwer zu entdecken, weil Abfragen einfach keine Ergebnisse liefern.
Diese Alerts feuern, wenn Metriken ohne erwartete Labels ankommen:

**Datei:** `apps/mimir/prod/files/mimir/alerts-label-integrity.yaml`

```yaml
groups:
  - name: mimir_label_integrity
    rules:

      # Pod-Metriken ohne namespace-Label (Enrichment-Pipeline kaputt)
      - alert: PodMetricsMissingNamespaceLabel
        expr: |
          count(container_cpu_usage_seconds_total{namespace=""}) > 0
          or
          count(container_cpu_usage_seconds_total) unless count(container_cpu_usage_seconds_total{namespace!=""}) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Pod-Metriken ohne namespace-Label"
          description: "container_cpu_usage_seconds_total hat keine namespace-Labels. K8s-Attribute-Enrichment in Alloy funktioniert nicht."

      # Metriken ohne cluster-Label (inject_cluster fehlgeschlagen)
      - alert: MetricsMissingClusterLabel
        expr: |
          count(up{cluster=""}) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Metriken ohne cluster-Label"
          description: "Metriken kommen ohne cluster-Label an. Resource-Injection in Alloy fehlgeschlagen."
```

### 1.4 Ruler selbst überwachen

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

### Szenario B: Alloy-Pipeline liefert k8s-Labels

Prüft: K8s-Attribute-Enrichment (namespace, pod, node, cluster) funktioniert.

```bash
# Stichprobe: eine Container-Metrik mit allen Labels ausgeben
curl -sf \
  -H "X-Scope-OrgID: $ORG" \
  "$MIMIR/prometheus/api/v1/query" \
  --data-urlencode 'query=container_cpu_usage_seconds_total{namespace="mimir"}' \
  | jq '[.data.result[0].metric | {namespace, pod, container, node, cluster}]'

# Erwartetes Ergebnis (alle Felder müssen nicht-leer sein):
# [{ "namespace": "mimir", "pod": "mimir-ingester-0",
#    "container": "ingester", "node": "...", "cluster": "prod-bwcloud" }]
```

**Checkliste Label-Vollständigkeit:**

| Label | Quelle in Alloy | Erwarteter Wert (Beispiel) |
|---|---|---|
| `cluster` | `inject_cluster` Resource-Processor | `prod-bwcloud` |
| `namespace` | `k8sattributes` → `mirror_legacy_labels` | `mimir`, `alloy`, etc. |
| `pod` | `k8sattributes` → `mirror_legacy_labels` | `mimir-ingester-0` |
| `container` | `k8sattributes` → `mirror_legacy_labels` | `ingester` |
| `node` | `k8sattributes` | `<k8s-node-name>` |

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
| Label-Vollständigkeit | Szenario B (curl + jq) | Nach Alloy-Änderungen |
| Alle Scrape-Quellen aktiv | Szenario C (curl-Schleife) | Nach Alloy-Änderungen |
| Metrik-Volumen plausibel | Szenario D (curl) | Nach Cluster-Events |
| Ruler feuert Alerts | Szenario E (curl Prometheus API) | Nach Ruler-Konfigurationsänderungen |
| Rule-Expressions korrekt | Szenario F (promtool) | Lokal, vor jedem Commit |
| Config-Reload funktioniert | Szenario G (curl + kubectl) | Nach Rule-Änderungen |
