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
   - Bevorzugt Mimir Alertmanager als zentrale Runtime-Notification-Plane
   - Mimir-Ruler-Alerts laufen nativ in den Mimir Alertmanager
   - Grafana-managed Alerts sollen, soweit technisch zuverlässig möglich, an den Mimir Alertmanager weitergeleitet werden
   - Grafana Contact Points / Notification Policies bleiben nur Fallback oder Übergangslösung, wenn Forwarding nicht möglich ist

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

**Provisionierung (Checksum-basierter Job):**

- Ein Helm-Template (`ruler-rules-configmap.yaml`) bündelt alle passenden Dateien in einer ConfigMap `mimir-rules-bundle`.
- Ein dynamischer Kubernetes-Job (`mimir-rules-sync-<checksum>`) wird bei jeder Änderung neu erstellt.
- **Double-Checksum Mechanismus:** Der Name des Jobs basiert auf der Checksumme der **Regeldateien PLUS der Mimir-Infrastruktur-Konfiguration**.
- **Stabilisierter Job-Template:** Um Konflikte mit immutablen Feldern in Kubernetes zu vermeiden (z.B. `spec.selector`), nutzt das Job-Template eine minimalistische Definition. Kubernetes generiert die notwendigen Selektoren automatisch.
- **Hintergrund:** Da der Mimir Ruler aktuell flüchtigen Speicher (`emptyDir`) nutzt, gehen geladene Regeln bei einem Pod-Neustart verloren. Ein Neustart wird oft durch Infrastruktur-Änderungen (z.B. Memory-Limits) ausgelöst. Durch die Kopplung der Job-Checksumme an die Infrastruktur stellt Argo CD sicher, dass nach jedem potenziellen Neustart des Rulers auch der Sync-Job erneut läuft und die Regeln wieder einspielt.

**Technische Rationale (Warum dieses Modell?):**
1. **API-Standard:** Mimir nutzt intern eine komplexe, Base64-kodierte Verzeichnisstruktur für Rule-Dateien. Der API-Weg via `mimirtool` ist der offizielle und robusteste Weg.
2. **GitOps-Konformität:** Da Kubernetes-Jobs "immutable" sind, ist der Name-Rotation-Ansatz (via Checksum) der einzig zuverlässige Weg in GitOps, um sicherzustellen, dass Logik tatsächlich ausgeführt wird.
3. **Selbstheilung:** Der Job nutzt Kubernetes-native Retries (`backoffLimit`), um auf die Verfügbarkeit der Mimir-API zu warten, ohne auf Shell-Skripte in distroless Images angewiesen zu sein.

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

### 5.1 Empfohlenes Modell: Hybrid bei Regeln, zentral bei Notifications

Das aktuell im Repo angelegte Modell soll beibehalten, aber beim Notification-Routing stärker vereinheitlicht werden:

#### Mimir Ruler bleibt primär für Prometheus-/Upstream-Regeln

Nutzen für:

- Upstream-Regeln
- Plattformregeln im Prometheus-Format
- GitOps-gesteuerte Kernalerts

#### Grafana Alerting ist primär für Grafana-managed Alerts

Nutzen für:

- Teamregeln
- UI-erstellte Regeln
- fachbereichsspezifische Alerts

#### Mimir Alertmanager ist die bevorzugte zentrale Notification-Plane

Nutzen für:

- Mimir-Ruler-Alerts
- Grafana-managed Alerts, wenn Grafana sie an den Mimir Alertmanager weiterleitet
- einheitliche Contact Points, Notification Policies, Customer-Routen und spätere Eskalationen

So bleibt die Regelerstellung flexibel, während das Routing nicht doppelt gepflegt werden muss.

#### Grafana bleibt die zentrale Sicht

Grafana dient als:

- UI für Regelstatus
- UI für Alertmanager-Sichtbarkeit
- Einstiegspunkt für Betrieb und Troubleshooting

### 5.2 Warum kein harter Single-Plane-Ansatz für die Regelerstellung

Ein vollständig vereinheitlichtes Alerting auf nur einem Regeltyp wäre zwar einfacher in der Theorie, ist im aktuellen Repo-Stand aber nicht der natuerliche Pfad.

Gruende:

- Der Mimir-Ruler-Pfad ist für Upstream- und Plattformregeln gut geeignet.
- Grafana-managed Rules sind für Kunden und UI-nahe Teams deutlich zugänglicher.
- Eine Konvertierung aller Upstream-Regeln in Grafana-Regeln würde Wartung und Upstream-Updates erschweren.
- Ein Verbot von Grafana-UI-Alerts würde die Customer Experience verschlechtern.

Deshalb gilt: **Rule-Authoring darf hybrid bleiben, Notification-Routing soll möglichst zentral über Mimir Alertmanager laufen.**

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

Die im Repo vorhandene Grafana-Konfiguration ist aktuell nur ein technischer Platzhalter. Zusätzlich besitzt der Mimir Alertmanager nur eine minimale Fallback-Konfiguration. Vor produktivem Einsatz muessen echte Receiver, Verteiler und Routing-Bedingungen im bevorzugten Zielsystem gepflegt werden.

Empfohlener Zielpfad:

1. Mimir Alertmanager als zentrale Notification-Plane konfigurieren.
2. Grafana-managed Alerts an den Mimir Alertmanager weiterleiten.
3. Grafana Contact Points / Notification Policies nur als Fallback oder Übergangslösung verwenden.
4. Customer-Routing über `namespace` bzw. `k8s_namespace_name` und bei Grafana-managed Alerts optional über Folder-/Customer-Labels abbilden.

### 8.6 Self-Service für Customer Notification Routing

Ein zentrales Routing im Mimir Alertmanager darf nicht bedeuten, dass jede Kundenänderung manuell durch das Observability-Team umgesetzt werden muss.

Für Customer-Self-Service gibt es drei Betriebsmodelle:

1. **GitOps-only:** Kunden stellen Pull Requests für eigene Contact Points und Namespace-Routen. Das ist maximal auditierbar, aber langsam.
2. **Grafana UI auf Mimir Alertmanager:** Grafana verwaltet den Mimir Alertmanager als Alertmanager-Datasource. Nutzer können dort, bei passenden Berechtigungen, Contact Points, Notification Policies und Silences bearbeiten. Runtime-System bleibt Mimir Alertmanager.
3. **Customer-owned Routing-Fragmente:** Kunden pflegen eigene Routing-Fragmente in ihren GitOps-Bereichen. Die Plattform rendert daraus eine zentrale Alertmanager-Konfiguration.

Nicht empfohlen ist der Versuch, Mimir-/Prometheus-Alerts erst an Grafanas eingebauten Alertmanager weiterzuleiten, damit dort das zentrale Routing passiert. Grafanas eingebauter Alertmanager ist primär für Grafana-managed Alerts gedacht. Für Mimir-/Prometheus-Alerts ist der Mimir Alertmanager der passendere zentrale Notification-Plane.

Empfohlenes Zielbild:

- kurzfristig: Mimir Alertmanager zentral, Customer-Routen per MR oder kontrollierter Grafana-UI-Verwaltung
- langfristig: customer-owned GitOps-Fragmente mit klaren Guardrails
- Guardrail: Kunden dürfen nur eigene Namespace-/Customer-Routen pflegen; globale Routen bleiben Plattform-owned

Da Customer-GitOps-Repositories direkt auf Cust-Clustern deployen und nicht automatisch vom Observability-Repository konsumiert werden, ist eine rein zentrale Mimir-Alertmanager-Konfiguration für Customer-Self-Service nur mit zusätzlicher Integrationslogik möglich.

Pragmatischer Betriebsmodus:

- Plattform-/Upstream-Alerts bleiben im Mimir Ruler und routen über den Mimir Alertmanager.
- Customer-owned Alerts dürfen weiterhin als Grafana-managed Alerts per UI erstellt, exportiert und über den Grafana Operator aus dem Customer-GitOps-Repository deployed werden.
- Customer-eigene Notification Policies dürfen für Customer-owned Alerts in Grafana liegen.
- Plattform-Alerts, die Kunden betreffen, werden im Mimir Alertmanager über `namespace` bzw. `k8s_namespace_name` an Kunden geroutet.

Damit gibt es zwar zwei Notification-Planes, aber mit klarer fachlicher Ownership:

| Alert-Typ | Eigentümer | Notification-Plane |
|---|---|---|
| Plattform-/Upstream-Alerts | Plattform/Observability | Mimir Alertmanager |
| Customer-App-Alerts | Kunde | Grafana Alerting / Grafana-managed Notification Policy |
| Plattform-Alerts mit Customer-Auswirkung | Plattform + Kunde | Mimir Alertmanager mit Namespace-Routing |

Langfristige Alternative für vollständige Zentralisierung:

- Ein eigener `CustomerAlertRoute`-Controller oder Operator auf Cust-Clustern.
- Kunden deployen deklarative Routing-Fragmente in ihren eigenen Repositories.
- Der Controller validiert Namespace-Ownership und synchronisiert erlaubte Fragmente in den zentralen Mimir Alertmanager.
- Dadurch kann Customer-GitOps den zentralen Alertmanager beeinflussen, ohne direkten Vollzugriff auf globale Routing-Regeln zu erhalten.

### 8.7 Notification-Onboarding für neue Kunden

Beim Onboarding neuer Kunden reicht es nicht, nur Namespaces und Anwendungen anzulegen. Plattform-Alerts können sofort für diese Namespaces feuern, z.B. Kubernetes-, Quota-, Pending-Pod-, Restart- oder HPA-Alerts. Ohne zusätzliche Automation müsste das Observability- oder Cust-Cluster-Team jedes Mal manuell Contact Points und Notification-Routen anlegen.

Deshalb braucht jeder Kunde ein **Notification-Onboarding-Profil**.

Empfohlener Mindeststandard:

1. Jeder Customer-Namespace ist eindeutig einem Kunden zuordenbar.
   - bevorzugt über Namespace-Label, z.B. `observability.bwcloud.io/customer=<customer-id>`
   - alternativ über Namenskonvention, z.B. `<customer-id>-*`
2. Jeder Kunde pflegt ein `CustomerNotificationProfile` oder `CustomerAlertRoute` in seinem eigenen GitOps-Repository.
3. Dieses Profil enthält Contact Points und erlaubte Namespace-Pattern.
4. Plattform-Alerts mit Customer-Bezug routen über `namespace` oder `k8s_namespace_name`.
5. Fehlt ein Profil, gehen Alerts nicht verloren, sondern landen bei `ch-cust-cluster` und `ch-platform-all`.

Kurzfristig kann dies über einen zentralen Customer-Notification-Router umgesetzt werden:

- Mimir Alertmanager routet customer-bezogene Alerts an einen generischen `customer-router-webhook`.
- Der Router liest `namespace`, `k8s_namespace_name` oder Customer-Labels aus dem Alert.
- Der Router sucht den passenden Customer Contact Point aus `CustomerNotificationProfile`-Daten.
- Der Router sendet die Notification an die Kundenadresse oder fällt auf Cust-Cluster/Plattform zurück.

Damit muss der Mimir Alertmanager nicht für jeden neuen Kunden manuell neue Receiver bekommen. Neue Kunden können ihre Notification-Daten über ihr eigenes GitOps-Repository pflegen, während globale Plattform-Routen geschützt bleiben.

### 8.8 Delegierte Customer Notification Policy

Wenn ein Kunde seine Notification Policy selbst ändern möchte, sollte er nicht die globale Alertmanager-Root-Policy bearbeiten. Stattdessen bekommt er einen **delegierten Policy-Subtree** unterhalb seines eigenen Customer-/Namespace-Matchers.

Beispielhafte logische Struktur:

```text
global root
├── severity=critical → ch-platform-all, continue=true
├── namespace=~"customer-a-.*" → customer-a subtree, continue=true
│   ├── severity=critical, service=frontend → customer-a-frontend-oncall
│   ├── severity=critical                  → customer-a-critical
│   ├── severity=warning                   → customer-a-default
│   └── fallback                           → customer-a-default
└── fallback → ch-platform-all
```

Der Kunde pflegt in seinem eigenen GitOps-Repository ein Objekt wie `CustomerNotificationPolicy`. Dieses Objekt beschreibt nur Receiver und Routen innerhalb seines eigenen Scopes.

Erlaubt:

- eigene Receiver definieren
- eigene Routen unterhalb des Customer-Matchers definieren
- nach `severity`, `service`, `alertname`, `component`, `namespace` routen
- eigene Wiederholintervalle und Gruppierung setzen

Nicht erlaubt:

- globale Plattform-Routen ändern
- fremde Namespaces matchen
- zentrale Fallback-Receiver überschreiben
- fremde Kundenreceiver referenzieren

Technische Umsetzungsoptionen:

1. **Controller rendert Customer-Subtrees in den Mimir Alertmanager.**
   - Vorteil: ein zentraler Runtime-Alertmanager
   - Nachteil: eigener Controller/Operator nötig
2. **Customer-Router wertet Customer-Subtrees selbst aus.**
   - Vorteil: Mimir Alertmanager bleibt stabil und braucht nur eine generische Customer-Route
   - Nachteil: Router muss Matching, Grouping und Repeat-Logik nachbauen
3. **Für Customer-owned Grafana Alerts bleibt Grafana Notification Policy aktiv.**
   - Vorteil: sofort nutzbar mit Grafana Operator und Customer-GitOps
   - Nachteil: zweite Notification-Plane, aber fachlich auf Customer-owned Alerts begrenzt

Empfehlung:

- kurzfristig Customer-owned Grafana Policies für Customer-owned Alerts zulassen
- mittelfristig `CustomerNotificationProfile` für einfache Plattform-Alert-Zustellung einführen
- langfristig `CustomerNotificationPolicy` als delegierten Subtree einführen

#### Ablauf beim `customer-router-webhook`

Der `customer-router-webhook` ist aus Sicht des Mimir Alertmanagers ein finaler Receiver. Der Mimir Alertmanager sendet eine Webhook-Notification an den Router; danach wertet nicht mehr der Alertmanager, sondern der Router weiter aus.

```text
Mimir Alertmanager
   → receiver customer-router-webhook
      → HTTP POST mit Alertmanager-Webhook-Payload
         → Router liest Alert-Labels (`namespace`, `k8s_namespace_name`, `severity`, `service`, `alertname`)
         → Router bestimmt Customer über Namespace-Mapping
         → Router lädt `CustomerNotificationProfile` oder `CustomerNotificationPolicy`
         → Router bestimmt Zielreceiver
         → Router sendet E-Mail/Teams/Webhook an Kunden
         → bei unbekanntem Customer fallback an Cust-Cluster/Plattform
```

Für einfache Profile reicht Customer-Lookup plus Zustellung. Wenn Kunden eigene komplexe Policy-Bäume mit `continue`, eigenen Gruppierungen und Wiederholintervallen wollen, muss der Router diese Alertmanager-Semantik selbst nachbauen. In diesem Fall ist langfristig ein Controller, der validierte Customer-Subtrees direkt in den Mimir Alertmanager rendert, robuster.

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

1. Wie wird die Weiterleitung von Grafana-managed Alerts an den Mimir Alertmanager zuverlässig GitOps-fähig umgesetzt und validiert?
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
- **Mimir Alertmanager** ist die bevorzugte zentrale Notification-Plane.
- **Grafana** ist die zentrale Sicht auf Alerting, Regeln, Silences und Alertmanager-Status.
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
