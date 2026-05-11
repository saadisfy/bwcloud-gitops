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

**Voraussetzung:** `mimirtool` installiert, Zugriff auf `https://mimir.saadisfy.me`

```bash
export MIMIR_ADDRESS=https://mimir.saadisfy.me
export MIMIR_TENANT_ID=1
```

---

### Szenario A: Ingestion-Pfad funktioniert

Prüft: Daten kommen von Alloy an und sind sofort abfragbar.

```bash
# 1. Synthetics Metric pushen (remote_write Format)
cat <<EOF | curl -s --data-binary @- \
  -H "X-Scope-OrgID: 1" \
  -H "Content-Type: application/x-protobuf" \
  https://mimir.saadisfy.me/api/v1/push
# (remote_write via mimirtool ist einfacher:)
EOF

# Einfacher: mimirtool remote-write
mimirtool remote-write \
  --address=$MIMIR_ADDRESS \
  --id=$MIMIR_TENANT_ID \
  --metric='mimir_e2e_test{test="ingestion",cluster="prod-bwcloud"} 1'

# 2. Metric zurück abfragen (sollte sofort vorhanden sein)
mimirtool query \
  --address=$MIMIR_ADDRESS \
  --id=$MIMIR_TENANT_ID \
  'mimir_e2e_test{test="ingestion"}'

# Erwartetes Ergebnis: value=1, Label cluster="prod-bwcloud" vorhanden
```

---

### Szenario B: Alloy-Pipeline liefert k8s-Labels

Prüft: K8s-Attribute-Enrichment (namespace, pod, node, cluster) funktioniert.

```bash
# Stichprobe: Container-Metriken mit vollständigen Labels abfragen
mimirtool query \
  --address=$MIMIR_ADDRESS \
  --id=$MIMIR_TENANT_ID \
  'container_cpu_usage_seconds_total{namespace="mimir"}' \
  | jq '.data.result[0].metric | {namespace, pod, container, node, cluster}'

# Erwartetes Ergebnis (alle Labels müssen vorhanden und nicht-leer sein):
# {
#   "namespace": "mimir",
#   "pod": "mimir-ingester-0",
#   "container": "ingester",
#   "node": "<node-name>",
#   "cluster": "prod-bwcloud"
# }
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
# Für jeden erwarteten "Job" eine Signatur-Metrik abfragen:

JOBS=(
  "container_cpu_usage_seconds_total"   # cadvisor (kubelet scrape)
  "kubelet_node_name"                   # kubelet
  "kube_pod_info"                       # kube-state-metrics
  "node_cpu_seconds_total"              # node-exporter
  "alloy_build_info"                    # alloy self-scrape
  "cortex_request_duration_seconds_sum" # mimir self-scrape
)

for metric in "${JOBS[@]}"; do
  result=$(mimirtool query \
    --address=$MIMIR_ADDRESS \
    --id=$MIMIR_TENANT_ID \
    "${metric}{cluster=\"prod-bwcloud\"}" 2>/dev/null | jq '.data.result | length')
  echo "${metric}: ${result} series"
done

# Erwartetes Ergebnis: Jede Metrik hat > 0 series
# 0 series = diese Scrape-Quelle fehlt
```

---

### Szenario D: Metrik-Volumen plausibel

Prüft: Die Anzahl an aktiven Serien liegt in einem erwarteten Bereich.
Zu wenig Series = Scrapes fehlen. Zu viele = mögliches Cardinality-Problem.

```bash
# Gesamte aktive Series für Tenant 1
mimirtool query \
  --address=$MIMIR_ADDRESS \
  --id=$MIMIR_TENANT_ID \
  'sum(cortex_ingester_memory_series{cluster="prod-bwcloud"})'

# Series-Breakdown nach Namespace (Top-10)
mimirtool query \
  --address=$MIMIR_ADDRESS \
  --id=$MIMIR_TENANT_ID \
  'topk(10, count by (namespace) ({namespace!="", cluster="prod-bwcloud"}))'

# Empfehlung: Baseline nach erstem erfolgreichen Deploy festhalten
# und in Schicht-1-Alert als Schwellwert eintragen (s. AlloyIngestionRateLow)
```

---

### Szenario E: Alert-Evaluation funktioniert (Ruler Smoke-Test)

Prüft: Der Ruler lädt Rules, evaluiert sie und sendet Alerts an den Alertmanager.

```bash
# 1. Geladene Rules überprüfen
mimirtool rules list \
  --address=$MIMIR_ADDRESS \
  --id=$MIMIR_TENANT_ID

# Erwartetes Ergebnis: Alle Rule-Groups aus files/ sind gelistet
# (kubernetes-apps, mimir_alerts, mimir_custom_alerts, etc.)

# 2. Aktuelle Alert-States abfragen (welche Rules sind gerade "pending" oder "firing")
mimirtool rules list \
  --address=$MIMIR_ADDRESS \
  --id=$MIMIR_TENANT_ID \
  --output-dir=/tmp/rules-dump

# 3. Alertmanager erreichbar und konfiguriert
mimirtool alertmanager get \
  --address=$MIMIR_ADDRESS \
  --id=$MIMIR_TENANT_ID
# Erwartetes Ergebnis: Config vorhanden (kein 404)

# 4. Test-Alert deployen der garantiert feuert
# In eine temporäre Datei apps/mimir/prod/files/mimir/alerts-smoketest.yaml:
cat <<'EOF'
groups:
  - name: smoketest
    rules:
      - alert: RulerSmokeTest
        expr: vector(1) == 1   # feuert immer
        for: 1m
        labels:
          severity: none
          test: "true"
        annotations:
          summary: "Ruler Smoke-Test — kann nach Verifikation gelöscht werden"
EOF
# → committen, warten bis Reloader neu startet, dann in Alertmanager UI prüfen
# → danach Datei wieder löschen
```

---

### Szenario F: Mimir Ruler Config-Reload verifizieren

Prüft: Wenn sich Rules in Git ändern, landen sie auch wirklich im Ruler.

```bash
# Vor einer Rule-Änderung: Anzahl Rules merken
BEFORE=$(mimirtool rules list --address=$MIMIR_ADDRESS --id=$MIMIR_TENANT_ID | wc -l)

# → Neue Rule zur Datei hinzufügen, committen, pushen

# Warten bis Reloader den Pod neu gestartet hat (~60-90s)
kubectl rollout status deployment/mimir-ruler -n mimir --timeout=120s

# Nach dem Restart: Anzahl Rules prüfen
AFTER=$(mimirtool rules list --address=$MIMIR_ADDRESS --id=$MIMIR_TENANT_ID | wc -l)

echo "Vorher: $BEFORE Zeilen, Nachher: $AFTER Zeilen"
# AFTER > BEFORE = neue Rule wurde aufgenommen
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
| Ingestion Pfad E2E | Szenario A | Nach Änderungen |
| Label-Vollständigkeit | Szenario B | Nach Alloy-Änderungen |
| Alle Scrape-Quellen aktiv | Szenario C | Nach Alloy-Änderungen |
| Metrik-Volumen plausibel | Szenario D | Nach Cluster-Events |
| Ruler feuert Alerts | Szenario E | Nach Ruler-Konfigurationsänderungen |
| Config-Reload funktioniert | Szenario F | Nach Rule-Änderungen |
