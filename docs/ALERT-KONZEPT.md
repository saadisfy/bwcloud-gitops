# Alert-Konzept

Dieses Dokument beschreibt das Alerting-Zielbild, den aktuellen Ist-Zustand im Repository und ein belastbares Betriebsmodell für den Stack aus Alloy, Mimir und Grafana.

Es ist als Bruecke zwischen Architektur, GitOps-Umsetzung und späterer Alert-Regelpflege gedacht.

---

## 1. Ziel und Scope

### Ziele

- Störungen im Plattformbetrieb frueh erkennen.
- Echte Incident-Signale von rein informativen Signalen trennen.
- Alerts GitOps-fähig, reviewbar und reproduzierbar verwalten.
- Eine klare Trennung zwischen Regelquelle, Evaluierung und Notification-Routing schaffen.
- Grafana als zentrale Sicht auf Alerts, Regeln und Alertmanager nutzen.

### Im Scope

- Metrics-basierte Alerts auf Basis von Mimir.
- Grafana-managed Alerts für Team- und UI-nahe Regeln.
- Mimir Ruler für Prometheus-/Datasource-managed Regeln.
- Notification Routing ueber Alertmanager bzw. Grafana Alerting.
- Label- und Routing-Standard.
- GitOps-Workflow für Alert-Regeln.

### Ausserhalb des aktuellen Scope

- Logs-basiertes Alerting mit Loki.
- Trace-basiertes Alerting mit Tempo.
- PagerDuty/Opsgenie/ServiceNow-Integrationen.
- Vollständiges Multi-Cluster-Routing.

Hinweis: Tempo und Loki werden in der Observability-Doku als Zielbild erwähnt, sind für das aktuelle Alerting im Repo aber noch kein belastbarer Umsetzungspfad.

---

## 2. Aktueller Ist-Zustand im Repo

### 2.1 Metrikfluss

Der aktuelle Stack ist produktionsnah für Metriken aufgebaut:

1. Alloy sammelt und reichert Metriken an.
2. Alloy sendet per OTLP/HTTP an Mimir.
3. Alle internen Metriken laufen unter `X-Scope-OrgID = 1`.
4. Grafana greift per Mimir-Datasource auf dieselben Daten zu.

### 2.2 Alerting-Pfade

Im Repo sind zwei getrennte, aber komplementäre Alerting-Pfade angelegt:

#### Pfad A: Mimir datasource-managed Alerts

- Regeldateien im Prometheus-Format liegen unter `apps/mimir/prod/files/**/alerts*.yaml`.
- Diese Dateien werden automatisch in einer zentralen ConfigMap `mimir-rules-bundle` gebündelt.
- Das `mimir-ruler` Deployment wird durch einen **dynamischen Job** ergänzt (`mimir-rules-sync-<checksum>`), der bei jeder Änderung der Regeln das `mimirtool` nutzt, um diese gegen den Mimir-Gateway zu pushen.
- **GitOps Loop:** Da der Job einen eindeutigen Namen pro Stand hat, wird er von Argo CD bei jeder Änderung zuverlässig neu erstellt und ausgeführt.
- Der Mimir Ruler evaluiert die Regeln für Tenant `1`.
- Firing Alerts werden an den Mimir Alertmanager gesendet.

Dieser Pfad ist für plattformnahe, versionierte und stabil laufende Regeln gedacht.

#### Pfad B: Grafana-managed Alerts

- Grafana ist mit `manageAlerts: true` an die Mimir-Datasource angebunden.
- Grafana kann eigene Alert-Regeln als `GrafanaAlertRuleGroup` provisionieren.
- Die Provisionierung kann aus Values oder aus exportierten `alert-rules*.yaml` Dateien erfolgen.
- Contact Points und Notification Policies werden ueber den Grafana Operator provisioniert.

Dieser Pfad ist für teamnahe, UI-getriebene oder iterativ entwickelte Regeln gedacht.

### 2.3 Aktuelle Schwächen im Ist-Zustand

- Grafana Contact Points sind aktuell nur mit einem Platzhalter-Empfänger (`dummy@example.com`) konfiguriert.
- Die Root-Notification-Policy in Grafana routet derzeit nur auf einen Default-Receiver.
- Der Mimir Alertmanager besitzt aktuell nur eine minimale `fallbackConfig` ohne echte produktive Integrationen.
- Für Grafana-exportierte Alert-Regeln sind aktuell keine echten `alert-rules*.yaml` im Repo eingecheckt.
- Das fachliche Alert-Zielbild ist umfangreicher als der aktuell wirklich implementierte Runtime-Zustand.

---

## 3. Architekturprinzipien

### 3.1 Tenant-Standard

für interne Plattform-Metriken und Alerts gilt verbindlich:

- Tenant: `1`
- Header: `X-Scope-OrgID: 1`

Das gilt für:

- Alloy Export nach Mimir
- Grafana Mimir Datasource
- Grafana Alertmanager Datasource
- Mimir Ruler Sync

### 3.2 Trennung von Verantwortungen

Das Alerting wird logisch in drei Ebenen getrennt:

1. **Signalquelle**  
   Metriken aus Kubernetes, Mimir, Alloy, Argo CD, Kargo und weiteren Exportern.

2. **Regel-Evaluierung**  
   - Mimir Ruler für Prometheus-/Datasource-managed Regeln
   - Grafana Alerting für Grafana-managed Regeln

3. **Benachrichtigung und Routing**  
   - Mimir Alertmanager für Mimir-Ruler-Alerts
   - Grafana Contact Points / Notification Policies für Grafana-managed Alerts

### 3.3 Betriebsprinzip

- Plattformnahe Standard-Alerts sollen bevorzugt dateibasiert und GitOps-gesteuert sein.
- Experimentelle oder teamspezifische Regeln duerfen in Grafana entstehen, muessen aber exportiert und versioniert werden, sobald sie produktiv werden.
- Grafana bleibt die zentrale Sicht auf Regeln und Alerting-Status.
- Direkte, nicht versionierte UI-änderungen ohne Rueckfuehrung ins Repo sollen vermieden werden.

---

## 4. Source-of-Truth-Modell

### 4.1 Datasource-managed Rules in Mimir

**Kanonische Quelle:**

- `apps/mimir/prod/files/**/alerts*.yaml`

**Provisionierung (Sidecar-Init):**

- Ein Helm-Template (`ruler-rules-configmap.yaml`) bündelt alle passenden Dateien in einer ConfigMap `mimir-rules-bundle`.
- **Sidecar-Init Ablauf:**
    1. Der Init-Container `copy-mimirtool` stellt das `mimirtool`-Binary in einem geteilten Volume bereit.
    2. Der Sidecar-Container `rules-sync` wartet nach dem Start des Pods auf die lokale API (`localhost:8080/ready`).
    3. Sobald bereit, werden die Regeln via API registriert.
- Da dieser Vorgang Teil der Pod-Definition ist, wird er bei **jedem Neustart** des Ruler-Pods automatisch ausgeführt.

**Technische Rationale (Warum dieses Modell?):**
1. **API-Standard:** Mimir nutzt intern eine komplexe, Base64-kodierte Verzeichnisstruktur für Rule-Dateien. Der API-Weg via `mimirtool` ist der offizielle und robusteste Weg.
2. **Lebenszyklus-Kopplung:** Durch den Sidecar-Ansatz ist der Regel-Sync untrennbar mit dem Pod verbunden. Ein Neustart (egal ob durch Error oder Config-Change) zieht immer einen frischen Sync nach sich.
3. **GitOps & Reloader:** Änderungen in Git führen über den Reloader zum Pod-Restart, was wiederum den Sidecar-Sync triggert.

**Zielsystem:**

- Mimir Ruler, Tenant `1`

**Geeignet für:**

- Plattform-Alerts
- Offizielle Upstream-Alerts
- Stabile Standard-Regeln
- Regeln mit klarer Runbook-/Ownership-Zuordnung

### 4.2 Grafana-managed Rules aus Exportdateien

**Kanonische Quelle:**

- `apps/grafana/prod/files/**/alert-rules*.yaml`
- `apps/grafana/prod/files/**/alert-rules*.yml`

**Provisionierung:**

- Helm rendert pro exportierter Gruppe eine `GrafanaAlertRuleGroup`.
- Dieser Exportpfad ist der aktuell klare Dateipfad für Grafana-managed Regeln im prod-Setup.

**Zielsystem:**

- Grafana Alerting via Grafana Operator

**Geeignet für:**

- Team-spezifische Alerts
- UI-basierte Iteration
- Regeln mit Grafana-spezifischem Ausdrucksmodell

### 4.3 Grafana-managed Rules aus Values

**Kanonische Quelle:**

- `grafanaOperatorCRs.alerting` in den Grafana Values

**Status aktuell:**

- Es existiert die Struktur für Folder/Alerting, aber aktuell noch kein signifikanter produktiver Regelbestand in den prod Values.
- Der alternative Import von Prometheus-Dateien in Grafana ist zwar templated vorhanden, im prod-Setup aber durch `syncPrometheusRules: false` deaktiviert.

### 4.4 Contact Points und Notification Policies

**Kanonische Quelle:**

- `grafanaOperatorCRs.contactPoints`
- `grafanaOperatorCRs.notificationPolicies`

**Status aktuell:**

- Platzhalterkonfiguration vorhanden.
- Echte produktive Receiver und Routing-Matrix fehlen noch.

### 4.5 Recording Rules

**Aktueller Stand:**

- Recording Rules werden jetzt konsistent über den gleichen Mechanismus wie Alert Rules verwaltet.
- Sie befinden sich in Dateien namens `alerts-rules.yaml` oder `recording-rules*.yaml` (glob: `alerts*.yaml`).
- Sie werden zusammen mit den Alerts in das Mimir Filesystem-Backend geladen.

**Konzeptentscheidung:**
- Recording Rules werden im gleichen Mimir-Ruler-Pfad wie Alert Rules geführt, um die Konsistenz der Metriken sicherzustellen.

---

## 5. Empfohlenes Zielbild für den Betrieb

### 5.1 Empfohlenes Modell: Hybrid mit klaren Rollen

Das aktuell im Repo angelegte Modell soll beibehalten und sauber operationalisiert werden:

#### Mimir Alertmanager ist primär für Mimir-Ruler-Alerts

Nutzen für:

- Upstream-Regeln
- Plattformregeln im Prometheus-Format
- GitOps-gesteuerte Kernalerts

#### Grafana Alerting ist primär für Grafana-managed Alerts

Nutzen für:

- Teamregeln
- UI-erstellte Regeln
- fachbereichsspezifische Alerts

#### Grafana bleibt die zentrale Sicht

Grafana dient als:

- UI für Regelstatus
- UI für Alertmanager-Sichtbarkeit
- Einstiegspunkt für Betrieb und Troubleshooting

### 5.2 Warum kein harter Single-Plane-Ansatz im ersten Schritt

Ein vollständig vereinheitlichtes Alerting auf nur einer Notification-Plane wäre zwar einfacher in der Theorie, ist im aktuellen Repo-Stand aber nicht der natuerliche Pfad.

Gruende:

- Der Mimir-Ruler-Pfad ist bereits auf den Mimir Alertmanager ausgerichtet.
- Grafana-managed Rules haben ein eigenes, operatorfreundliches Provisionierungsmodell.
- Eine fruehe Vereinheitlichung wuerde mehr Umbau als unmittelbaren Mehrwert erzeugen.

---

## 6. Label- und Routing-Standard

Jede produktive Alert-Regel soll mindestens die folgenden Labels tragen:

### Pflicht-Labels

- `severity`
- `service`
- `component`

### Empfohlene Routing-Labels

- `domain`
- `owner`
- `clusterTier`

### Bedeutung der Labels

#### `severity`

- `critical`: unmittelbarer Handlungsbedarf
- `warning`: zeitnahe Pruefung erforderlich
- `info`: informativ, kein Incident per se

#### `service`

Beispiele:

- `kubernetes`
- `argocd`
- `kargo`
- `crossplane`
- `kyverno`
- `mimir`
- `grafana`
- `otel`

#### `component`

Beispiele:

- `node`
- `controller`
- `api-server`
- `ingester`
- `ruler`
- `alertmanager`
- `deployment`
- `promotion`

#### `domain`

Beispiele:

- `platform`
- `gitops`
- `devexperience`
- `customer`
- `observability`
- `security`

#### `owner`

Beispiele gemäss aktueller Planung:

- `S`
- `GG`
- `L`
- `M`
- `B`
- `distribution`

#### `clusterTier`

- `customer`
- `non-customer`

### Mindestanforderung an Annotations

Jede produktive Regel soll mindestens enthalten:

- `summary`
- `description`

Optional, aber empfohlen:

- `runbook_url`
- `dashboard_uid`
- `panel_id`

---

## 7. Alert-Domänen

Die vorhandene Fachplanung deckt folgende Domänen ab.

### 7.1 Cluster Health

Beispiele:

- Node NotReady
- Disk Pressure
- Memory Pressure
- Kubelet down
- API-Server Fehlerquote
- Pods stuck Pending
- CrashLoopBackOff

### 7.2 GitOps / Argo CD

Beispiele:

- App OutOfSync
- App Health Degraded
- AppSet Generation Error
- Repo-Server down

### 7.3 Promotion Pipeline / Kargo

Beispiele:

- Promotion Failed
- Warehouse stale
- Freight not verified
- Stage unhealthy

### 7.4 Observability

Beispiele:

- Grafana down
- Mimir Distributor/Ingester down
- Ingestion Drop
- OTel/Alloy Exportfehler

### 7.5 Security / Governance / Infrastruktur

Beispiele:

- Crossplane Provider down
- Managed Resource not Ready
- Kyverno Webhook failures
- Certificate Renewal failed

### 7.6 Customer Workloads

Beispiele:

- Rollout stuck
- HPA an Maximalgrenze
- Quota hoch
- Pod Restarts

### Priorisierung für den Rollout

Empfohlene Reihenfolge:

1. Observability-Stack selbst
2. Cluster Health
3. Argo CD / Kargo
4. Zertifikate / Ingress
5. Customer-Workloads
6. Security-/Governance-Domänen

So wird zuerst die Ueberwachung des Ueberwachers stabilisiert.

---

## 8. Notification-Konzept

### 8.1 Startmodell

für den Einstieg ist E-Mail ausreichend, solange das Routing klar ist.

Empfängerarten:

1. direkte verantwortliche Person
2. Team-/Bereichsverteiler
3. Teams-Channel-Mailadresse

### 8.2 Routing-Regeln

Routing soll primär ueber Labels erfolgen:

- `severity`
- `service`
- `domain`
- `owner`
- `clusterTier`

### 8.3 Grundregeln je Severity

#### `critical`

- kurze `group_wait`
- kurze `group_interval`
- kurze `repeat_interval`
- direkte Person plus Verteiler

#### `warning`

- Team-/Owner-basierte Zustellung
- deutlich längere Wiederholung

#### `info`

- nur Verteiler oder Team-Kanal
- keine Incident-Charakteristik

### 8.4 Fallback

Jedes Routing benötigt eine belastbare Fallback-Route auf ein zentrales Plattform-Postfach oder einen Plattform-Kanal.

### 8.5 Aktuelle Luecke

Die im Repo vorhandene Grafana-Konfiguration ist aktuell nur ein technischer Platzhalter. Vor produktivem Einsatz muessen echte Receiver, Verteiler und Routing-Bedingungen gepflegt werden.

---

## 9. Betriebsmodell und GitOps-Workflow

### 9.1 Grundsatz

Alerting wird wie Anwendungskonfiguration behandelt:

- änderungen per Pull Request
- Review durch Plattform-/Service-Verantwortliche
- Merge in Git
- Deployment durch Argo CD

### 9.2 Workflow für Mimir-Regeln

1. Regeldatei unter `apps/mimir/prod/files/.../alerts*.yaml` anlegen oder ändern.
2. PR mit Query, Labels, Annotationen und Runbook-Kontext erstellen.
3. Nach Merge synchronisiert Argo CD den Mimir-Release.
4. Argo CD erkennt den neuen Job `mimir-rules-sync-<checksum>` und führt diesen aus.
5. Der Job lädt die Regeln in die Mimir-API.
6. Regelstatus wird in Grafana (Dropdown: `mimir`) und über Mimir sichtbar.

### 9.3 Workflow für Grafana-managed Regeln

1. Regel in Grafana iterativ erstellen oder ändern.
2. Vor produktivem Einsatz Export in `alert-rules*.yaml`.
3. Datei im Repo versionieren.
4. Provisionierung über Grafana Operator.

### 9.4 DoD für jede produktive Regel

Eine Regel gilt erst als produktionsreif, wenn:

- Query fachlich nachvollziehbar ist
- `severity`, `service`, `component` gesetzt sind
- `domain` und `owner` gepflegt sind, sofern Routing darauf basiert
- `summary` und `description` vorhanden sind
- ein Test für Firing und Resolve durchgeführt wurde
- der Empfängerpfad verifiziert wurde

---

## 10. Validierung und Teststrategie

### Technische Validierung

- Regeldatei ist syntaktisch gültig.
- Tenant `1` wird konsistent verwendet.
- `mimir-rules-sync-<checksum>` Job läuft erfolgreich durch.
- Regeln sind über die Mimir Rules API (Dropdown in Grafana) sichtbar.
- Regeln erscheinen in Grafana Alerting (Datenquelle: `mimir`).

### Funktionale Validierung

- Test-Alert feuert wie erwartet.
- Notification kommt beim richtigen Empfänger an.
- Resolve-Nachricht wird korrekt verarbeitet.
- Labels sind konsistent genug für Routing und Filterung.

### Operative Validierung

- Kein massiver Alert-Noise.
- Kein unerwartetes `NoData` bei Standardmetriken.
- Keine unklaren Alerts ohne Handlungsanweisung.

---

## 11. Offene Entscheidungen und Risiken

### Offene Entscheidungen

1. Soll das Routing langfristig stärker ueber Mimir Alertmanager oder stärker ueber Grafana zentralisiert werden?
2. Wo sollen Recording Rules dauerhaft verwaltet werden?
3. Welche Alert-Domänen gelten als verpflichtender Plattform-Standard und welche nur als Referenzkatalog?
4. Wie wird später Multi-Cluster-Routing abgebildet?
5. Welche Empfänger und Teams-Channel sind produktiv verbindlich?

### Risiken

- Platzhalter-Receiver fuehren zu Scheinsicherheit.
- UI-änderungen ohne Rueckfuehrung ins Repo fuehren zu Drift.
- Nicht vorhandene Metriken können geplante Alerts unbrauchbar machen.
- Zu viele `critical` Alerts fuehren zu Alarm-Fatigue.
- Unklare Ownership macht Alerts operativ wertlos.

---

## 12. Konkrete Empfehlungen für die nächsten Schritte

### Kurzfristig

1. Echte Grafana Contact Points und Notification Policies hinterlegen.
2. Kernalerts für Observability und Cluster Health produktiv verdrahten.
3. Alert-Labels vereinheitlichen.
4. Den Tenant-Standard `1` in allen Alerting-Pfaden beibehalten.

### Mittelfristig

1. Recording Rules sauber von Alert Rules trennen.
2. Grafana-Exportpfad für Team-Alerts etablieren.
3. Argo CD- und Kargo-Alerts schrittweise produktiv machen.
4. Runbook-Links pro Kernalert nachziehen.

### Später

1. Multi-Cluster-Routing einfuehren.
2. Nicht-Metrik-Signale mit Loki/Tempo bewerten.
3. Eskalationslogik ueber E-Mail hinaus erweitern.

---

## 13. Verbindliche Leitlinie

Bis zu einer späteren Architekturentscheidung gilt für dieses Repository:

- **Mimir-Ruler-Regeln** sind die bevorzugte Quelle für plattformweite Standard-Alerts.
- **Grafana-managed Regeln** sind zulässig für teamnahe und iterativ gepflegte Alerts, muessen aber versioniert werden.
- **Grafana** ist die zentrale Sicht auf Alerting.
- **Tenant `1`** ist der verbindliche Standard für interne Metriken und Alerts.
- **Produktive Alerts ohne klare Labels, Ownership und Notification-Ziel sind nicht fertig.**

---

## 14. Referenzen im Repository

- `docs/Plan to realise alerts.md`
- `apps/grafana/alerting-plan.md`
- `docs/OBSERVABILITY.md`
- `docs/MIMIR.md`
- `apps/mimir/prod/values.yaml`
- `apps/mimir/base/values.yaml`
- `apps/mimir/prod/templates/ruler-rules-sync.yaml`
- `apps/mimir/prod/files/mimir/alerts.yaml`
- `apps/grafana/base/values.yaml`
- `apps/grafana/prod/values.yaml`
- `apps/grafana/prod/templates/grafana-operator-managed-alerts-from-grafana-exports.yaml`
- `apps/grafana/prod/templates/grafana-operator-managed-alerts-from-prometheus-files.yaml`
- `apps/grafana/prod/templates/grafana-operator-contactpoints.yaml`
- `apps/grafana/prod/templates/grafana-operator-notification-policies.yaml`
- `apps/grafana/prod/files/mimir/rules.yaml`
- `apps/alloy/config.alloy`
