# Observability Plattform — Testkonzept

**System:** Mimir, Alloy, Grafana  
**Deployment:** Argo CD / GitOps  
**Dokumenttyp:** Testkonzept und Testdurchführungsleitfaden  
**Version:** 1.0  
**Status:** Entwurf zur Review

---

## 1. Ziel des Testkonzepts

Ziel dieses Testkonzepts ist der Nachweis, dass die Observability-Plattform zuverlässig
Metriken sammelt, speichert, abfragt, visualisiert und zur Alarmierung verwendet.

Die Plattform besteht aus folgenden Kernkomponenten:

- **Alloy** zur Sammlung und Weiterleitung von Metriken
- **Mimir** zur Annahme, Speicherung, Abfrage und Regel-Auswertung von Metriken
- **Grafana** zur Visualisierung, Exploration und Anzeige von Alerts
- **Argo CD** zur deklarativen Bereitstellung der Komponenten

Das Testkonzept beschreibt:

- welche Testebenen genutzt werden,
- welche Komponenten geprüft werden,
- welche Risiken durch die Tests abgedeckt werden,
- welche Akzeptanzkriterien gelten,
- welche Tests automatisiert werden können,
- welche Tests manuell in Int/UAT durchzuführen sind.

---

## 2. Scope

### 2.1 Im Scope

- Metrik-Ingestion von Alloy nach Mimir
- Mimir-Komponenten: Distributor, Ingester, Querier, Query-Frontend, Ruler, Alertmanager, Compactor, Store-Gateway
- Grafana-Erreichbarkeit, Datasource-Anbindung und Dashboard-Anzeige
- Mimir Ruler und Alertmanager-Integration
- Grafana Alerting-Anzeige
- GitOps-Deployment über Argo CD
- grundlegende SSO-/Zugriffstests für Grafana
- Performance-Smoke-Tests
- kontinuierliche Plattform-Health-Alerts
- Restart- und Resilienztests

### 2.2 Nicht im Scope

- vollständige Penetrationstests
- vollständige Chaos-Engineering-Kampagnen
- mehrtägige Last- und Soak-Tests
- fachliche Vollprüfung jedes einzelnen Dashboard-Panels
- Tests für Logs oder Traces, sofern nicht Bestandteil der Plattform
- Backup-/Restore-Vollabnahme

---

## 3. Testparameter

Um das Dokument wartbar zu halten, werden konkrete URLs und Clusterwerte als Parameter geführt.

```bash
export MIMIR_URL="https://mimir.saadisfy.me"
export GRAFANA_URL="https://grafana.saadisfy.me"
export ORG_ID="1"
export CLUSTER="prod-bwcloud"

# Grafana API-Zugriff via Service Account Token (empfohlen)
# TODO: Evaluieren ob Basic Auth für Admin-User deaktiviert werden soll
#       sobald Service Account Token Workflow etabliert ist.
#       Aktuell: GRAFANA_TOKEN bevorzugen, GRAFANA_USER/PASS als lokale Fallback-Option.
export GRAFANA_TOKEN="<grafana-service-account-token>"
```

> **Hinweis zu Grafana-Auth:**  
> Die Grafana API wird in diesem Dokument primär mit `GRAFANA_TOKEN` (Service Account Token) genutzt.
> Das ist CI-tauglicher und vermeidet Probleme mit SSO-Only-Setups, wo Basic Auth
> deaktiviert sein kann. `GRAFANA_USER` / `GRAFANA_PASS` bleiben als lokale Fallback-Option.
> **TODO:** Später tiefer evaluieren, ob Basic Auth-Zugriff aktiv deaktiviert werden soll.

In produktionsnahen Umgebungen dürfen Zugangsdaten nicht fest im Testskript hinterlegt werden.
Secrets sind aus einem sicheren Secret Store oder aus CI/CD-Variablen zu laden.

---

## 4. Testhierarchie

```
┌─────────────────────────────────────────────────────────────────┐
│  Ebene 4: Blackbox E2E                                          │
│  Vollständige Pipeline aus Nutzerperspektive                    │
│  "Ich sehe Metriken im Grafana-Dashboard"                       │
├─────────────────────────────────────────────────────────────────┤
│  Ebene 3: Integrationstests                                     │
│  Zusammenspiel mehrerer Komponenten                             │
│  "Alloy schreibt Metriken nach Mimir"                           │
├─────────────────────────────────────────────────────────────────┤
│  Ebene 2: Komponententests                                      │
│  Einzelne Komponente isoliert verifiziert                       │
│  "Mimir-Gateway ist erreichbar"                                 │
├─────────────────────────────────────────────────────────────────┤
│  Ebene 1: Unit- und Konfigurationstests                         │
│  Lokale Prüfung ohne laufenden Cluster                          │
│  "Alert-Regeln bestehen promtool-Tests"                         │
└─────────────────────────────────────────────────────────────────┘
```

Jede Ebene baut auf der darunterliegenden auf. Ebene 1 läuft vor jedem Commit bzw. in der CI.
Ebene 4 wird nach vollständigem Deployment in Int/UAT durchgeführt.

---

## 5. Rollen und Verantwortlichkeiten

| Rolle | Verantwortung |
|---|---|
| DevOps/Plattform-Team | Erstellung und Pflege der Tests, Auswertung technischer Fehler |
| Entwickler | Pflege von Alert-Regeln, Dashboards und Konfigurationen |
| Betrieb | Bewertung von Betriebsfähigkeit, Monitoring und Alarmierung |
| UAT/Testverantwortliche | Durchführung manueller Blackbox-Tests |
| Security/Identity-Team | Prüfung von SSO, Rollen und Zugriffsschutz |

---

## 6. Ebene 1: Unit- und Konfigurationstests

**Wann:** Lokal vor jedem Commit, automatisierbar in CI  
**Tool:** `promtool`  
**Cluster:** nicht benötigt

### Risiken

| Risiko | Abdeckung durch Test |
|---|---|
| Alert-Regel ist syntaktisch falsch | `promtool check rules` |
| Alert feuert nie, zu früh oder bei Normalzustand | `promtool test rules` |

### TC-UNIT-001: Alert-Regeln syntaktisch prüfen

```bash
promtool check rules apps/mimir/prod/files/mimir/*.yaml
```

**Akzeptanzkriterium:** Alle Rule-Dateien sind syntaktisch gültig.

### TC-UNIT-002: Alert-Regeln fachlich mit synthetischen Zeitreihen prüfen

`promtool test rules` ist ein **Unit-Test-Runner für PromQL-Alert-Expressions** — kein Lint-Tool.
Es wird **kein laufender Cluster benötigt**.

**Was es fängt (was ArgoCD nicht kann):**

- Tippfehler in Metriknamen (`cortex_distributor_recieved_...`)
- Falsche `rate()`-Zeitfenster (Alert feuert nie weil `[1m]` statt `[5m]`)
- Falsche `for`-Dauer (Alert feuert zu früh oder zu spät)
- Falsche Label-Selektoren im `expr`
- Alerts die bei Normalwerten feuern würden (False Positives)

ArgoCD prüft nur ob das YAML syntaktisch gültig ist — die inhaltliche Korrektheit der
Alert-Logik bleibt ohne diesen Test ungeprüft.

```bash
# Installation: brew install prometheus (enthält promtool)
promtool test rules apps/mimir/tests/*.yaml
# Erwartetes Ergebnis: "SUCCESS: N tests passed"
```

Beispiel-Testdatei `apps/mimir/tests/test-pipeline-health.yaml`:

```yaml
rule_files:
  - ../prod/files/mimir/alerts-pipeline-health.yaml

tests:
  # Szenario: Ingestion stoppt → Alert muss feuern
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

  # Szenario: Ingestion läuft normal → kein Alert (False-Positive-Test)
  - interval: 1m
    input_series:
      - series: 'cortex_distributor_received_samples_total{cluster="prod-bwcloud"}'
        values: '0+500x10'
    alert_rule_test:
      - eval_time: 6m
        alertname: AlloyIngestionStopped
        exp_alerts: []
```

### TC-UNIT-003: Helm-Charts lokal prüfen (optional)

> **Optional — ArgoCD rendert und validiert beim Sync selbst.**  
> Der einzige Mehrwert ist **Feedback-Loop-Geschwindigkeit**: `helm lint` schlägt in ~1s
> lokal fehl, ein ArgoCD-Sync-Error ist erst nach ~30–60s im UI sichtbar. Wer schnelles
> lokales Feedback bevorzugt, kann es als Pre-Commit-Schritt nutzen — zwingend nötig ist es nicht.

```bash
# Optional — nur bei Bedarf
helm lint apps/mimir/prod/
helm lint apps/grafana/prod/
helm lint apps/alloy/prod/
```

---

## 7. Ebene 2: Komponententests

**Wann:** Nach jedem Deployment einer einzelnen Komponente  
**Tool:** `curl`, `kubectl`  
**Cluster:** erforderlich

### 7.1 Mimir

#### TC-MIMIR-001: Gateway erreichbar

```bash
curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/prometheus/api/v1/labels" \
  | jq -e '.status == "success"'
```

**Akzeptanzkriterium:** HTTP 200 und `status=success`.

#### TC-MIMIR-002: Pods Ready

```bash
kubectl get pods -n mimir
```

**Akzeptanzkriterium:** Alle relevanten Pods sind `Running` und `Ready`:
distributor, ingester, querier, query-frontend, ruler, alertmanager, compactor, store-gateway, gateway.

#### TC-MIMIR-003: Ingester im Ring aktiv

```bash
curl -sf "${MIMIR_URL}/ingester/ring" | grep -c "ACTIVE"
```

> **Hinweis:** Je nach Ingress/Gateway-Routing ist dieser Endpunkt nicht extern erreichbar.
> Ggf. als internen Test via `kubectl port-forward` ausführen.

**Akzeptanzkriterium:** Mindestens ein Ingester ist `ACTIVE`.

#### TC-MIMIR-004: Ruler hat Rules geladen

```bash
curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/prometheus/api/v1/rules" \
  | jq -e '.data.groups | length > 0'
```

**Akzeptanzkriterium:** Mindestens eine Rule-Gruppe ist geladen.

#### TC-MIMIR-005: PVCs gebunden

```bash
kubectl get pvc -n mimir
```

**Akzeptanzkriterium:** Alle PVCs sind `Bound`.

#### TC-MIMIR-006: Alertmanager erreichbar

```bash
curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/alertmanager/api/v2/status" \
  | jq '.cluster.status'
```

**Akzeptanzkriterium:** Alertmanager-Status ist vorhanden und fehlerfrei.

**Checkliste Mimir:**

| ID | Check | Erwartetes Ergebnis |
|---|---|---|
| TC-MIMIR-001 | Gateway erreichbar | HTTP 200, status=success |
| TC-MIMIR-002 | Alle Pods Ready | 0 Pods nicht-Ready |
| TC-MIMIR-003 | Ingester im Ring | ≥ 1 ACTIVE |
| TC-MIMIR-004 | Ruler lädt Rules | Mindestens 1 Rule-Gruppe |
| TC-MIMIR-005 | PVCs Bound | Alle PVCs gebunden |
| TC-MIMIR-006 | Alertmanager erreichbar | Status vorhanden |

---

### 7.2 Alloy

#### TC-ALLOY-001: Alloy-Pods laufen

```bash
kubectl get pods -n alloy
```

**Akzeptanzkriterium:** Alle Alloy-Pods sind `Running` und `Ready`.

#### TC-ALLOY-002: Alloy-Metriken sind in Mimir vorhanden

```bash
curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/prometheus/api/v1/query" \
  --data-urlencode "query=alloy_build_info{cluster=\"${CLUSTER}\"}" \
  | jq -e '(.data.result | length) > 0'
```

**Akzeptanzkriterium:** Mindestens eine `alloy_build_info`-Zeitreihe vorhanden.

#### TC-ALLOY-003: Keine kritischen Fehler in Logs

```bash
kubectl logs -n alloy -l app.kubernetes.io/name=alloy --tail=200 \
  | grep -Ei "error|failed|panic" \
  | grep -vi "level=debug"
```

**Akzeptanzkriterium:** Keine unerwarteten Fehler.  
Hinweis: Treffer müssen bewertet werden — nicht jede Error-Zeile ist automatisch ein Testfehler.

#### TC-ALLOY-004: Exporter-Queue nicht voll

```bash
curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/prometheus/api/v1/query" \
  --data-urlencode "query=otelcol_exporter_queue_size{cluster=\"${CLUSTER}\"}" \
  | jq -e '(.data.result[0].value[1] | tonumber) < 800'
# Ziel: < 80% von typischer Kapazität 1000
```

**Akzeptanzkriterium:** Queue-Auslastung unter 80% der Kapazität.

#### TC-ALLOY-005: Metrik-Typ-Metadaten korrekt

> **Hintergrund (Muster aus `grafana/alloy` k8s-Tests):**  
> Alloys `deps/mimir.go` enthält `QueryMetadata()` — eine Assertion die prüft ob Metriken in
> Mimirs `/api/v1/metadata` mit korrektem `type` (counter/gauge/histogram) registriert sind.
> Das fängt Konfigurationsfehler wie falsches `honor_labels`, Metric-Renaming in `config.alloy`
> oder falsche OTLP-Konvertierung — Dinge die Scrape-Coverage-Tests (TC-INT-004) nicht sehen.
> **Wir testen damit unsere `config.alloy`, nicht Alloy als Applikation.**

```bash
# Prüft ob key metrics den erwarteten Typ haben
# (counter statt gauge würde auf Konvertierungsfehler hinweisen)
declare -A EXPECTED_TYPES=(
  ["container_cpu_usage_seconds_total"]="counter"
  ["node_cpu_seconds_total"]="counter"
  ["kube_pod_info"]="gauge"
  ["alloy_build_info"]="gauge"
  ["cortex_request_duration_seconds_sum"]="counter"
)
for metric in "${!EXPECTED_TYPES[@]}"; do
  expected="${EXPECTED_TYPES[$metric]}"
  actual=$(curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
    "${MIMIR_URL}/prometheus/api/v1/metadata?metric=${metric}" \
    | jq -r ".data.\"${metric}\"[0].type // empty")
  [[ "$actual" == "$expected" ]] \
    && echo "✅ $metric: type=$actual" \
    || echo "❌ $metric: erwartet=$expected, tatsächlich=${actual:-nicht vorhanden}"
done
```

**Akzeptanzkriterium:** Alle geprüften Metriken haben den erwarteten Typ in Mimirs Metadata-Endpoint.

**Checkliste Alloy:**

| ID | Check | Erwartetes Ergebnis |
|---|---|---|
| TC-ALLOY-001 | Pods Running/Ready | 1/1 |
| TC-ALLOY-002 | `alloy_build_info` in Mimir | version-Label gesetzt |
| TC-ALLOY-003 | Keine ERROR-Logs | 0 unerwartete Fehler-Zeilen |
| TC-ALLOY-004 | Queue nicht voll | < 80% Kapazität |
| TC-ALLOY-005 | Metrik-Typ-Metadaten korrekt | type=counter/gauge wie erwartet |

---

### 7.3 Grafana

#### TC-GRAFANA-001: Grafana Health API

```bash
curl -sf "${GRAFANA_URL}/api/health" | jq -e '.database == "ok"'
```

**Akzeptanzkriterium:** HTTP 200 und Datenbankstatus `ok`.

#### TC-GRAFANA-002: Datasource Mimir vorhanden

```bash
curl -sf -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  "${GRAFANA_URL}/api/datasources" \
  | jq '[.[] | {name, type, url}]'
```

**Akzeptanzkriterium:** Datasource vom Typ `prometheus` mit Verweis auf Mimir vorhanden.

#### TC-GRAFANA-003: Datasource Health

```bash
curl -sf -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  "${GRAFANA_URL}/api/datasources/uid/<mimir-uid>/health" \
  | jq -e '.status == "OK"'
```

**Akzeptanzkriterium:** Datasource-Status ist `OK`.

#### TC-GRAFANA-004: Dashboards vorhanden

```bash
curl -sf -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  "${GRAFANA_URL}/api/search?type=dash-db" \
  | jq -e 'length > 0'
```

**Akzeptanzkriterium:** Mindestens ein Dashboard vorhanden.

**Checkliste Grafana:**

| ID | Check | Erwartetes Ergebnis |
|---|---|---|
| TC-GRAFANA-001 | `/api/health` | HTTP 200, database=ok |
| TC-GRAFANA-002 | Datasource Mimir vorhanden | Typ `prometheus`, URL auf Mimir-Gateway |
| TC-GRAFANA-003 | Datasource Health | Status "OK" |
| TC-GRAFANA-004 | Dashboards vorhanden | > 0 Dashboards |

---

## 8. Ebene 3: Integrationstests

**Wann:** Nach Änderungen die mehrere Komponenten betreffen  
**Tool:** `curl`, `kubectl`  
**Cluster:** erforderlich

### 8.1 Alloy → Mimir: Ingestion-Pfad

#### TC-INT-001: Ingestion-Rate größer 0

```bash
curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/prometheus/api/v1/query" \
  --data-urlencode "query=sum(rate(cortex_distributor_received_samples_total{cluster=\"${CLUSTER}\"}[2m]))" \
  | jq -e '(.data.result[0].value[1] | tonumber) > 0'
```

**Akzeptanzkriterium:** Ingestion-Rate ist numerisch größer 0.

#### TC-INT-002: Keine verworfenen Samples

```bash
curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/prometheus/api/v1/query" \
  --data-urlencode "query=sum(rate(cortex_discarded_samples_total{cluster=\"${CLUSTER}\"}[5m]))" \
  | jq '.data.result'
```

**Akzeptanzkriterium:** Wert ist 0 oder kein Ergebnis.

### 8.2 Label-Vollständigkeit pro Scrape-Target

#### TC-INT-003: Pflichtlabels vorhanden

```bash
check_labels() {
  local desc=$1 query=$2; shift 2; local labels=("$@")
  local result
  result=$(curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
    "${MIMIR_URL}/prometheus/api/v1/query" \
    --data-urlencode "query=$query" \
    | jq -r '.data.result[0].metric // empty')
  [[ -z $result ]] && { echo "❌ $desc: keine Daten"; return 1; }
  for label in "${labels[@]}"; do
    val=$(echo "$result" | jq -r ".\"$label\" // empty")
    [[ -z $val ]] && echo "❌ $desc: Label '$label' fehlt" \
                  || echo "✅ $desc: $label=$val"
  done
}

check_labels "cadvisor"           "container_cpu_usage_seconds_total{cluster=\"${CLUSTER}\"}" namespace pod container node cluster
check_labels "kube-state-metrics" "kube_pod_info{cluster=\"${CLUSTER}\"}"                    namespace pod node cluster
check_labels "node-exporter"      "node_cpu_seconds_total{cluster=\"${CLUSTER}\"}"            node cluster
check_labels "alloy"              "alloy_build_info{cluster=\"${CLUSTER}\"}"                  cluster
check_labels "mimir"              "cortex_request_duration_seconds_sum{cluster=\"${CLUSTER}\"}" namespace cluster
```

**Akzeptanzkriterium:** Alle Pflichtlabels sind vorhanden.

### 8.3 Scrape-Coverage

#### TC-INT-004: Erwartete Scrape-Ziele liefern Metriken

```bash
declare -A CHECKS=(
  ["cadvisor"]="container_cpu_usage_seconds_total{cluster=\"${CLUSTER}\"}"
  ["kubelet"]="kubelet_node_name{cluster=\"${CLUSTER}\"}"
  ["kube-state-metrics"]="kube_pod_info{cluster=\"${CLUSTER}\"}"
  ["node-exporter"]="node_cpu_seconds_total{cluster=\"${CLUSTER}\"}"
  ["alloy-self"]="alloy_build_info{cluster=\"${CLUSTER}\"}"
  ["mimir-self"]="cortex_request_duration_seconds_sum{cluster=\"${CLUSTER}\"}"
)
for name in "${!CHECKS[@]}"; do
  count=$(curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
    "${MIMIR_URL}/prometheus/api/v1/query" \
    --data-urlencode "query=${CHECKS[$name]}" \
    | jq '.data.result | length')
  echo "$([[ $count -gt 0 ]] && echo ✅ || echo ❌)  $name ($count series)"
done
```

**Akzeptanzkriterium:** Jedes Scrape-Ziel liefert ≥ 1 Zeitreihe.

### 8.4 Mimir Ruler → Alertmanager (Smoke-Test)

#### TC-INT-005: Smoke-Test-Alert feuert

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
        annotations:
          summary: "Smoke-Test-Alert für Ruler/Alertmanager"
```

```bash
git add . && git commit -m "test: ruler smoketest" && git push
# → warten ~90s bis Reloader Pod neu startet

curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/prometheus/api/v1/alerts" \
  | jq '[.data.alerts[] | select(.labels.alertname=="RulerSmokeTest")]'

# Aufräumen:
git rm apps/mimir/prod/files/mimir/alerts-smoketest.yaml
git commit -m "test: remove smoketest" && git push
```

**Akzeptanzkriterium:** Alert erscheint als aktiv. Nach Aufräumen verschwindet er.

### 8.5 Mimir → Grafana über Datasource-Proxy

#### TC-INT-006: Query über Grafana Datasource Proxy

```bash
curl -sf -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  "${GRAFANA_URL}/api/datasources/proxy/uid/<mimir-uid>/api/v1/query" \
  --data-urlencode "query=up{cluster=\"${CLUSTER}\"}" \
  | jq -e '(.data.result | length) > 0'
```

**Akzeptanzkriterium:** Über Grafana-Proxy ist mindestens eine Mimir-Zeitreihe abfragbar.

### 8.6 Git-Push → Ruler lädt neue Rules

#### TC-INT-007: Config-Reload funktioniert

```bash
BEFORE=$(curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/prometheus/api/v1/rules" \
  | jq '.data.groups | length')
# → Neue Rule-Datei committen und pushen
kubectl rollout status deployment/mimir-ruler -n mimir --timeout=120s
AFTER=$(curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/prometheus/api/v1/rules" \
  | jq '.data.groups | length')
[[ $AFTER -gt $BEFORE ]] && echo "✅ Neue Rules geladen" || echo "❌ Keine Änderung"
```

**Akzeptanzkriterium:** Neue Rules werden nach GitOps-Sync in Mimir geladen.

### 8.8 Alertmanager-Config entspricht erwarteter Config

#### TC-INT-008: Alertmanager-Config-Validierung

> **Hintergrund (Muster aus `grafana/alloy` k8s-Tests):**  
> Alloys `deps/mimir.go` enthält `CheckAlertsConfig()` — vergleicht Mimirs tatsächliche
> Alertmanager-Config (`/api/v1/alerts`) mit einer erwarteten Datei.  
> Wir nutzen dasselbe Prinzip, um nach einem GitOps-Push zu prüfen ob unsere
> `alertmanager_config` (aus `apps/mimir/base/values.yaml`) korrekt in Mimir geladen wurde.
> **Wir testen unsere Konfiguration, nicht Alloy als Applikation.**

```bash
# Mimirs aktuelle Alertmanager-Config abrufen und gegen erwartete Struktur prüfen
curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/alertmanager/api/v2/status" \
  | jq -e '.
    | .cluster.status != null
    and (.uptime != null)
  '
# Prüft grundlegende Struktur

# Für tiefere Validierung: Receiver-Namen aus unserer values.yaml prüfen
# (anpassen an tatsächliche Receiver-Namen)
curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/alertmanager/api/v2/status" \
  | jq -e '[.config.receivers[].name] | contains(["default-receiver"])'
```

Alternativ mit gespeicherter erwarteter Ausgabe (exakter Vergleich):

```bash
# Erwartete Config einmalig speichern:
curl -sf -H "X-Scope-OrgID: ${ORG_ID}" \
  "${MIMIR_URL}/alertmanager/api/v1/alerts" \
  > apps/mimir/tests/expected_alertmanager_config.json

# Bei jedem Test vergleichen:
ACTUAL=$(curl -sf -H "X-Scope-OrgID: ${ORG_ID}" "${MIMIR_URL}/alertmanager/api/v1/alerts")
EXPECTED=$(cat apps/mimir/tests/expected_alertmanager_config.json)
[[ "$ACTUAL" == "$EXPECTED" ]] \
  && echo "✅ Alertmanager-Config entspricht erwartetem Stand" \
  || echo "❌ Alertmanager-Config weicht ab"
```

**Akzeptanzkriterium:** Mimirs Alertmanager-Config enthält die erwarteten Receiver und entspricht der in `values.yaml` definierten Konfiguration.

---

## 9. Ebene 4: Blackbox E2E

**Wann:** Nach vollständigem Deployment in Int, vor UAT-Abnahme  
**Perspektive:** Endnutzer — kein internes Wissen über Implementierung  
**Tool:** Browser (manuell), `curl` gegen öffentliche Endpunkte

### TC-E2E-001: Metrik-Durchlauf (vollständige Pipeline)

```
Alloy scrapet Node-Exporter
  → Mimir nimmt Samples an
    → Grafana-Dashboard zeigt node_cpu_seconds_total
      → Alert "NodeExporterMetricsMissing" ist NICHT aktiv
```

**Schritte (manuell):**
1. Grafana öffnen: `https://grafana.saadisfy.me`
2. Mit SSO anmelden
3. Explore → Datasource "Mimir" → Query: `node_cpu_seconds_total{cluster="prod-bwcloud"}`
4. Zeitreihe mit Labels `node` und `cluster` sichtbar
5. Alerting → Alert rules → `NodeExporterMetricsMissing` = Normal (nicht feuern)

**Akzeptanzkriterium:** Metriken sichtbar, Missing-Alert nicht aktiv.

### TC-E2E-002: Login und Zugriffskontrolle (SSO)

**Schritte (manuell):**
1. Privates Browser-Fenster: `https://grafana.saadisfy.me`
2. Redirect auf OIDC-Provider erscheint
3. Login mit berechtigtem SSO-Account
4. Dashboard-Übersicht sichtbar
5. Logout → erneuter Aufruf → kein Zugriff ohne Auth

**Akzeptanzkriterium:** Ohne Auth kein Zugriff. Mit berechtigtem Account Zugriff möglich.

### TC-E2E-003: Alert-Lifecycle (vollständige Kette)

```
Rule feuert in Mimir Ruler
  → Alert erscheint in Alertmanager
    → Grafana Alert-Tab zeigt "Firing"
      → Notification an Receiver (Webhook/Slack) zugestellt
```

**Schritte:**
1. Smoke-Test-Rule deployen (siehe TC-INT-005)
2. Nach ~2min: Grafana → Alerting → Alert rules → `RulerSmokeTest` = Firing
3. Alertmanager-API: `curl .../alertmanager/api/v2/alerts` → Alert aktiv
4. Webhook-Receiver (falls konfiguriert): Payload empfangen
5. Aufräumen: Rule-Datei entfernen und pushen

**Akzeptanzkriterium:** Alert vollständig durch die Kette verarbeitet.

### TC-E2E-004: Dashboard-Vollständigkeit

**Schritte (manuell):**
1. Grafana → Dashboards
2. Alle erwarteten Dashboards vorhanden und öffnen ohne Fehler
3. Kein Panel zeigt dauerhaft "No data" bei laufendem Cluster
4. Variablen (Namespace, Pod, Node) werden befüllt

**Akzeptanzkriterium:** Dashboards vorhanden und zeigen bei laufendem Cluster keine dauerhaften Fehler.

---

## 10. Negative Tests

| ID | Szenario | Erwartung |
|---|---|---|
| TC-NEG-001 | Falsche Tenant-ID bei Mimir-Query | Keine unberechtigte Datenanzeige |
| TC-NEG-002 | Falscher/kein Grafana-Token | Zugriff wird verweigert |
| TC-NEG-003 | Defekte Alert-Rule in CI | `promtool` schlägt fehl |
| TC-NEG-004 | Fehlendes Pflichtlabel | Label-Test schlägt fehl |
| TC-NEG-005 | Nicht vorhandene Datasource | Grafana-Datasource-Test schlägt fehl |
| TC-NEG-006 | Temporär gestoppte Ingestion | Pipeline-Health-Alert feuert |

Beispiel TC-NEG-001:

```bash
curl -i -H "X-Scope-OrgID: wrong-tenant" \
  "${MIMIR_URL}/prometheus/api/v1/query" \
  --data-urlencode 'query=up'
# Erwartetes Ergebnis: leeres Result oder Fehler — keine fremden Daten
```

---

## 11. Security- und Zugriffstests

| ID | Test | Erwartung |
|---|---|---|
| TC-SEC-001 | Grafana ohne Login öffnen | Redirect zu SSO oder Zugriff verweigert |
| TC-SEC-002 | Grafana mit berechtigtem User | Zugriff möglich |
| TC-SEC-003 | Grafana mit unberechtigtem User | Zugriff verweigert oder eingeschränkt |
| TC-SEC-004 | Admin-Funktionen mit normalem User | Keine Admin-Rechte sichtbar |
| TC-SEC-005 | Mimir-API ohne Tenant/Auth | Kein ungeschützter Datenzugriff |
| TC-SEC-006 | Secrets in Logs prüfen | Keine Passwörter/Tokens sichtbar |
| TC-SEC-007 | Datasource-Credentials | Keine Secrets im Frontend sichtbar |

---

## 12. GitOps- / Argo-CD-Tests

> **Hinweis zur Einordnung:**  
> Der Synchronisationsstatus (Synced/Healthy) von Argo-CD-Applications wird im laufenden Betrieb
> durch Alerting und Health-Probes auf dem Deployment kontinuierlich überwacht — das ist ein
> Bestandteil des Continuous Deployment, nicht des expliziten Continuous Testing.  
> Die folgenden Testfälle sind daher als **Abnahme-Checks** gedacht, nicht als laufende CI-Tests.

| ID | Test | Erwartung |
|---|---|---|
| TC-GITOPS-001 | Argo-CD Application Status | `Synced` und `Healthy` |
| TC-GITOPS-002 | Änderung an Rule-Datei committen | Änderung wird ausgerollt |
| TC-GITOPS-003 | Manuelle Drift im Cluster erzeugen | Argo CD erkennt `OutOfSync` |
| TC-GITOPS-004 | Rollback auf vorherigen Commit | Plattform kehrt in funktionsfähigen Zustand zurück |

```bash
# TC-GITOPS-001
argocd app get <app-name>
# Erwartetes Ergebnis: Sync Status = Synced, Health Status = Healthy
```

---

## 13. Restart- und Resilienztests (optional)

> **Einordnung:** Diese Tests sind sinnvoll zur Betriebsfähigkeitsabnahme, aber nicht bei
> jedem Standard-Testlauf erforderlich. Durchführung nach Freigabe, nicht in Prod ohne
> explizites Change-Freigabe.

| ID | Test | Erwartung |
|---|---|---|
| TC-RES-001 | Grafana-Pod neu starten | Grafana wieder erreichbar |
| TC-RES-002 | Alloy-Pod neu starten | Metrik-Ingestion erholt sich |
| TC-RES-003 | Mimir-Distributor neu starten | Write-Pfad erholt sich automatisch |
| TC-RES-004 | Mimir-Ruler neu starten | Rules werden wieder geladen |
| TC-RES-005 | Alertmanager neu starten | Alerts wieder sichtbar |
| TC-RES-006 | Historische Metrik nach Restart abfragen | Daten im Retention-Fenster verfügbar |

Beispiel:

```bash
kubectl rollout restart deployment/mimir-ruler -n mimir
kubectl rollout status deployment/mimir-ruler -n mimir --timeout=120s
# Danach: TC-MIMIR-004 erneut ausführen
```

---

## 14. Kontinuierliche Überwachung (Schicht 1 Alerts)

Diese Alerts laufen dauerhaft im Cluster und dienen sowohl dem Betrieb als auch der
kontinuierlichen Testabdeckung.

### 14.1 Pipeline-Health

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
          (
            sum(rate(cortex_discarded_samples_total{cluster="prod-bwcloud"}[5m]))
            /
            sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[5m]))
          ) > 0.05
          and
          sum(rate(cortex_distributor_received_samples_total{cluster="prod-bwcloud"}[5m])) > 0
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

### 14.2 Scrape-Coverage

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

### 14.3 Ruler-Self-Monitoring

```yaml
groups:
  - name: mimir_ruler_health
    rules:
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

## 15. Performance-Tests

**Wann:** Int-Stage, vor UAT  
**Tools:** Offizielles k6-Skript aus `grafana/mimir` oder `mimirtool loadgen`

### 15.1 k6 Smoke-Test

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
  -e K6_WRITE_TENANT_ID="${ORG_ID}" \
  -e K6_READ_TENANT_ID="${ORG_ID}" \
  -e K6_WRITE_REQUEST_RATE="1" \
  -e K6_WRITE_SERIES_PER_REQUEST="100" \
  -e K6_READ_REQUEST_RATE="1" \
  -e K6_DURATION_MIN="5"
```

### 15.2 Performance-Akzeptanzkriterien

| Kriterium | Zielwert |
|---|---|
| Write Success Rate | ≥ 99,9 % |
| Query-Latenz Durchschnitt | < 2 s |
| Query-Latenz p95 | < 3 s |
| Query-Latenz p99 | < 5 s |
| OOMKills | 0 |
| CrashLoops | 0 |
| Discarded Samples | 0 oder fachlich begründet |

### 15.3 Alternative: mimirtool loadgen

```bash
mimirtool loadgen \
  --write-url="${MIMIR_URL}/api/v1/push" \
  --query-url="${MIMIR_URL}/prometheus" \
  --active-series=1000 \
  --scrape-interval=15s \
  --tenant-id="${ORG_ID}"
```

---

## 16. Zuordnung zu Stages

### Dev

| Ebene | Tests | Automatisierbar |
|---|---|---|
| 1 — Unit | `promtool check rules`, `promtool test rules` | ✅ CI/pre-commit |
| 2 — Komponente | Pods Ready, Gateway erreichbar, Rules geladen | ✅ Script |
| 3 — Integration | Ingestion-Rate, Label-Checks, Scrape-Coverage | ✅ Script |
| Kontinuierlich | Schicht-1-Alerts laufen permanent | ✅ automatisch |

### Int / UAT

| Ebene | Tests | Automatisierbar |
|---|---|---|
| 1–3 | Alle Dev-Tests müssen bestehen | ✅ Voraussetzung |
| 4 — Blackbox E2E | Login/SSO, Dashboard, Alert-Lifecycle | ⚠️ Manuell |
| Negative Tests | Tenant-Isolation, Zugriffsschutz | ✅ Teilweise |
| Security | SSO, Rollen, unberechtigter Zugriff | ⚠️ Teilweise manuell |
| Performance | k6 Smoke-Test | ✅ k6 |
| Resilience | Restart-Tests | ⚠️ Mit Freigabe |

### Prod

| Ebene | Tests | Hinweis |
|---|---|---|
| Smoke Tests | Health, Datasource, Ingestion | Nur nicht-invasive Tests |
| Monitoring | Permanente Alerts | Pflicht |
| E2E | Nur lesende Prüfungen | Keine Test-Alerts ohne Abstimmung |
| Performance | Keine Lasttests ohne Freigabe | Risiko für Betrieb |
| Resilience | Keine Restart-Tests ohne Change-Freigabe | — |

---

## 17. Testfallübersicht

| ID | Ebene | Komponente | Testfall | Automatisiert |
|---|---|---|---|---|
| TC-UNIT-001 | 1 | Mimir | Alert-Regeln Syntax prüfen | Ja |
| TC-UNIT-002 | 1 | Mimir | Alert-Regeln mit promtool testen | Ja |
| TC-UNIT-003 | 1 | Helm | Helm-Charts linten | Optional |
| TC-MIMIR-001 | 2 | Mimir | Gateway erreichbar | Ja |
| TC-MIMIR-002 | 2 | Mimir | Pods Ready | Ja |
| TC-MIMIR-003 | 2 | Mimir | Ingester Ring aktiv | Ja |
| TC-MIMIR-004 | 2 | Mimir | Ruler lädt Rules | Ja |
| TC-MIMIR-005 | 2 | Mimir | PVCs Bound | Ja |
| TC-MIMIR-006 | 2 | Mimir | Alertmanager erreichbar | Ja |
| TC-ALLOY-001 | 2 | Alloy | Pods Ready | Ja |
| TC-ALLOY-002 | 2 | Alloy | Metriken in Mimir vorhanden | Ja |
| TC-ALLOY-003 | 2 | Alloy | Keine kritischen Logs | Ja |
| TC-ALLOY-004 | 2 | Alloy | Queue nicht voll | Ja |
| TC-ALLOY-005 | 2 | Alloy | Metrik-Typ-Metadaten korrekt | Ja |
| TC-GRAFANA-001 | 2 | Grafana | Health API | Ja |
| TC-GRAFANA-002 | 2 | Grafana | Datasource vorhanden | Ja |
| TC-GRAFANA-003 | 2 | Grafana | Datasource Health | Ja |
| TC-GRAFANA-004 | 2 | Grafana | Dashboards vorhanden | Ja |
| TC-INT-001 | 3 | Alloy/Mimir | Ingestion-Rate > 0 | Ja |
| TC-INT-002 | 3 | Mimir | Keine discarded Samples | Ja |
| TC-INT-003 | 3 | Mimir | Labels vollständig | Ja |
| TC-INT-004 | 3 | Gesamt | Scrape-Coverage | Ja |
| TC-INT-005 | 3 | Ruler/AM | Smoke-Test-Alert | Teilweise |
| TC-INT-006 | 3 | Grafana/Mimir | Datasource Proxy | Ja |
| TC-INT-007 | 3 | GitOps/Ruler | Config-Reload | Teilweise |
| TC-INT-008 | 3 | Mimir/Config | Alertmanager-Config-Validierung | Ja |
| TC-E2E-001 | 4 | Gesamt | Metrik-Durchlauf | Manuell |
| TC-E2E-002 | 4 | Grafana | Login/SSO | Manuell |
| TC-E2E-003 | 4 | Alerting | Alert-Lifecycle | Manuell |
| TC-E2E-004 | 4 | Grafana | Dashboard-Vollständigkeit | Manuell |

---

## 18. Akzeptanzkriterien für Abnahme

Die Plattform gilt als testseitig abnahmefähig, wenn folgende Kriterien erfüllt sind:

- [ ] Alle Unit- und Konfigurationstests bestehen
- [ ] Alle Mimir-Komponententests bestehen
- [ ] Alle Alloy-Komponententests bestehen
- [ ] Alle Grafana-Komponententests bestehen
- [ ] Ingestion von Alloy nach Mimir ist aktiv (Rate > 0)
- [ ] Erwartete Scrape-Ziele liefern Metriken
- [ ] Pflichtlabels (`cluster`, `namespace`, `pod`, `node`) vorhanden
- [ ] Ruler lädt Rules erfolgreich
- [ ] Smoke-Test-Alert durchläuft Ruler → Alertmanager → Grafana
- [ ] Grafana-SSO funktioniert
- [ ] Grafana-Dashboards vorhanden und nutzbar
- [ ] Keine kritischen Plattform-Alerts aktiv
- [ ] Keine OOMKills oder CrashLoops während des Testfensters
- [ ] Performance-Smoke-Test besteht definierte Schwellenwerte
- [ ] Testergebnisse dokumentiert
- [ ] Offene Abweichungen bewertet und freigegeben

---

## 19. Artefakte und TODOs

| Artefakt | Speicherort | Status |
|---|---|---|
| Testkonzept | `docs/mimir-test-konzept.md` | ✅ vorhanden |
| Ruler & Alerting Setup | `docs/mimir-ruler-alerting-setup.md` | ✅ vorhanden |
| Pipeline-Health Alerts | `apps/mimir/prod/files/mimir/alerts-pipeline-health.yaml` | ⚠️ noch anlegen |
| Scrape-Coverage Alerts | `apps/mimir/prod/files/mimir/alerts-scrape-coverage.yaml` | ⚠️ noch anlegen |
| Ruler-Health Alerts | `apps/mimir/prod/files/mimir/alerts-ruler-health.yaml` | ⚠️ noch anlegen |
| promtool Unit-Tests | `apps/mimir/tests/` | ⚠️ noch anlegen |
| Automatisierte Testskripte | `scripts/tests/` | ⚠️ noch anlegen |
| Testreport-Template | siehe §20 | ✅ vorhanden |

---

## 20. Testreport-Template

```markdown
# Testreport Observability-Plattform

## Allgemein

- Datum:
- Umgebung:
- Cluster:
- Tester:
- Version/Commit:

## Zusammenfassung

| Bereich | Ergebnis | Kommentar |
|---|---|---|
| Unit-Tests | PASS/FAIL | |
| Mimir | PASS/FAIL | |
| Alloy | PASS/FAIL | |
| Grafana | PASS/FAIL | |
| Integration | PASS/FAIL | |
| E2E | PASS/FAIL | |
| Performance | PASS/FAIL | |
| Security | PASS/FAIL | |

## Abweichungen

| ID | Beschreibung | Schweregrad | Entscheidung |
|---|---|---|---|

## Freigabe

- Freigegeben: Ja/Nein
- Freigegeben durch:
- Datum:
- Bedingungen/Auflagen:
```

---

## 21. Offene Fragen

- Welche Ziel-Last gilt für Int/UAT realistisch?
- Welche Dashboards sind für die Abnahme verpflichtend?
- Welche Rollen sollen in Grafana getestet werden?
- Ist ein Restore-Test Bestandteil der Abnahme?
- Gibt es mehrere Tenants oder nur `ORG_ID=1`?
- Dürfen Smoke-Test-Alerts in Int/UAT Notifications auslösen?
- Sollen Tests als CI-Job, Argo-CD-PostSync-Hook oder manuelles Script ausgeführt werden?
- **TODO:** Grafana Service Account Token Workflow evaluieren — wann wird Basic Auth deaktiviert?
