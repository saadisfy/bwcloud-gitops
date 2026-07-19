# Alert-Konzept

**Stand:** 2026-06-01
**Entscheidung:** Grafana-only Alerting — kein Mimir Ruler, kein Mimir Alertmanager als primäre Plane.

---

## 1. Intro: Begriffe und Komponenten

### 1.1 Alert Rules — Prometheus vs. Grafana

Es gibt zwei grundlegend verschiedene Typen von Alert Rules:

#### Prometheus-based Alert Rules (Datasource-managed)

- Format: natives Prometheus YAML (`groups[].rules[].alert`)
- Evaluation liegt **in der Datenquelle** — entweder im Prometheus-Server oder im Mimir Ruler
- Offizielle Upstream-Mixins (kubernetes-mixin, argocd-mixin, mimir-mixin) liefern dieses Format
- Regeln sind unabhängig von Grafana — keine UID-Bindung, keine Folder-ID
- Grafana kann diese Regeln in der UI anzeigen (read-only über Datasource-Dropdown), aber nicht besitzen

```yaml
groups:
  - name: kubernetes.rules
    rules:
      - alert: NodeNotReady
        expr: kube_node_status_condition{condition="Ready",status="true"} == 0
        for: 5m
        labels:
          severity: critical
          service: kubernetes
        annotations:
          summary: "Node {{ $labels.node }} is NotReady"
```

#### Grafana-managed Alert Rules

- Regeln liegen in Grafana (intern), laufen aber gegen beliebige Datasources per PromQL
- Evaluation durch den Grafana Alerting Engine
- Gebunden an: Datasource-UID, Folder-ID, Org-Kontext — nicht generisch portierbar
- GitOps-fähig via Grafana Operator CR `GrafanaAlertRuleGroup`
- Keine offiziellen Upstream-Bundles: Grafana veröffentlicht absichtlich keine fertigen Rule-Sets,
  weil Datasource-UIDs und Folder-IDs pro Installation individuell sind

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaAlertRuleGroup
metadata:
  name: node-alerts
spec:
  instanceSelector:
    matchLabels:
      dashboards: "grafana"
  folderRef: cluster-health
  rules:
    - uid: node-not-ready
      title: "Node NotReady"
      condition: B
      data:
        - refId: A
          datasourceUid: "<mimir-uid>"
          model:
            expr: 'kube_node_status_condition{condition="Ready",status="true"}'
        - refId: B
          datasourceUid: "__expr__"
          model:
            type: threshold
            conditions:
              - evaluator: { params: [1], type: lt }
      for: 5m
      labels:
        severity: critical
        service: kubernetes
```

### 1.2 Backends: Mimir Ruler und Alertmanager

#### Mimir Ruler

- Komponente innerhalb von Mimir; evaluiert Prometheus-Alert-Regeln tenant-spezifisch
- Regeln werden via `mimirtool rules load` in die Mimir API gepusht
- Sendet Firing Alerts **ausschliesslich** an einen konfigurierten Alertmanager-Endpoint (Mimir AM oder kompatibler Prometheus AM)
- Grafana Alertmanager ist kein offiziell supported Ziel für Mimir Ruler

```text
Prometheus-Regeln → mimirtool → Mimir API (Tenant 1)
→ Mimir Ruler evaluiert PromQL → Alert firing
→ Mimir Ruler → Alertmanager-Endpoint (nur Mimir AM)
```

#### Mimir Alertmanager (extern)

- Vollständig Prometheus-kompatibler Alertmanager als Teil von Mimir
- Konfiguration tenant-spezifisch via API (mimirtool oder Crossplane Mimir Provider)
- Format: Standard Alertmanager v2 YAML — identisch zu Prometheus Alertmanager
- Routing auf beliebige Labels möglich: `alertname`, `namespace`, `cluster`, `severity`, etc.
- Konfiguration per Grafana Operator **nicht möglich** (API fehlt, GitHub Issue > 1 Jahr offen)

#### Grafana Alertmanager (intern)

- In Grafana eingebaut; wird automatisch gestartet
- Empfängt Alerts von Grafana-managed Alert Rules (nicht von Mimir Ruler)
- Konfiguration via Grafana Operator CRs: `GrafanaContactPoint`, `GrafanaNotificationPolicy`
- Routing-Modell: identisch zu Prometheus Alertmanager v2
- Grafana UI zeigt Alertmanager-Dropdown: `Grafana` (intern) und `Mimir` (extern, read-only View)

### 1.3 Notification Policies und Contact Points

#### Contact Point

Definiert **wohin** eine Notification geht — Receiver-Konfiguration.

Unterstützte Typen: Email, Slack, Teams, Webhook, PagerDuty, Telegram, etc.

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaContactPoint
metadata:
  name: gitops-team-email
spec:
  instanceSelector:
    matchLabels:
      dashboards: "grafana"
  name: gitops-team-email
  type: email
  settings:
    addresses: "gg@company.com"
```

#### Notification Policy

Definiert **Routing-Regeln** — welche Alerts gehen zu welchem Contact Point.

- Baum-Struktur: Root Policy mit verschachtelten Routes
- Matching via Label-Matchers: `alertname`, `namespace`, `severity`, `service`, etc.
- Jede Route hat: `receiver`, `matchers`, `group_by`, `group_wait`, `group_interval`, `repeat_interval`
- Routing auf alle Labels möglich die ein Alert trägt — inkl. Labels aus Prometheus-Zeitreihen

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaNotificationPolicy
metadata:
  name: main-policy
spec:
  instanceSelector:
    matchLabels:
      dashboards: "grafana"
  subject:
    receiver: platform-all        # Root fallback
    groupBy: [alertname, namespace]
    routes:
      - receiver: gitops-team-email
        matchers:
          - name: service
            value: argocd
      - receiver: crossplane-team
        matchers:
          - name: service
            value: crossplane
```

#### Grafana OSS RBAC-Constraint

| Rolle | Contact Points | Notification Policies | Alert-Regeln |
|---|---|---|---|
| Admin | Lesen + Schreiben (UI + GitOps) | Lesen + Schreiben (UI + GitOps) | Lesen + Schreiben |
| Editor | Lesen (read-only UI) | Lesen (read-only UI) | Lesen + Schreiben |
| Viewer | Kein Zugriff auf Alerting-Menü | Kein Zugriff auf Alerting-Menü | Kein Zugriff |

> **REQUIREMENT:** Editor-User können Notification Policies und Contact Points nicht per UI anlegen
> oder ändern. Kunden (als Editor) können die Konfiguration lesen, aber kein UI-Self-Service für
> Notification Routing. Alle Notification-Konfigurationen laufen über GitOps (Admin-only).

---

## 2. Architekturentscheidung: Die zwei Hauptarchitekturen

Für die Verwaltung und Bereitstellung von Alerts und Benachrichtigungen gibt es zwei etablierte Hauptpfade:

### 2.1 Variante A: Pur Grafana Operator (Grafana-only Alerting)

In dieser Architektur wird die komplette Alerting-Konfiguration über den **Grafana Operator** abgewickelt. Der interne Grafana Alertmanager übernimmt das Benachrichtigungsrouting.

- **Datenfluss:** Grafana-Engine evaluiert Regeln via PromQL → Interner Grafana Alertmanager → Benachrichtigung.
- **Bereitstellung:** 
  * Dashboards, Contact Points und Notification Policies werden direkt als Grafana-Operator-CRDs deklariert.
  * Prometheus-basierte Rule-Dateien (z. B. Mixins) müssen entweder über Helm-Templates **on-the-fly in `GrafanaAlertRuleGroup` CRs konvertiert** oder manuell in der UI erstellt/umgewandelt werden.
- **Vorteile:**
  * Einfaches Setup mit nur einer einzigen Dependency (Grafana Operator).
  * Direkte UI-Sichtbarkeit und Editierbarkeit (falls Berechtigungen vorhanden).
- **Nachteile:**
  * Hoher Performance-Overhead auf der Grafana-Instanz, da Grafana alle Regeln selbst auswerten muss.
  * Keine native Mehrmandantenfähigkeit (Tenant-Isolation) im integrierten Alertmanager für getrennte Notification-Rules.

### 2.2 Variante B: Hybrid-Modell mit Crossplane (Mimir Ruler + Alertmanager) — *Aktuell Gewählt*

In dieser Architektur wird der Grafana Operator **ausschließlich** für Dashboards und Ordnerstrukturen genutzt. Das komplette Alerting und Routing läuft direkt in Mimir (Ruler und Alertmanager) und wird deklarativ via **Crossplane** provisioniert.

- **Datenfluss:** Mimir Ruler evaluiert Regeln lokal in der Datenquelle → Mimir Alertmanager (extern) → Benachrichtigung.
- **Bereitstellung:**
  * Dashboards und Folders laufen via Grafana Operator.
  * Mimir Rules und Recording Rules sowie die Alertmanager Config (Policies & Contact Points) werden via Crossplane Mimir Provider (`Rules` und `Config` CRs) direkt über die Mimir HTTP APIs provisioniert.
  * In Grafana wird die interne Alerting-Engine deaktiviert bzw. so konfiguriert (`unified_alerting.alertmanagers_choice: external`), dass sie alle in der UI erstellten Alerts direkt an den externen Mimir Alertmanager weiterleitet (`handleGrafanaManagedAlerts: true`).
- **Vorteile:**
  * Maximale Performance und Skalierbarkeit, da Regeln direkt in Mimir (verteilt im Ingest-Pfad/Ruler-Ring) evaluiert werden.
  * Native Mehrmandantenfähigkeit (Tenant-Isolation pro Namespace/Kunde).
  * Saubere Trennung der Zuständigkeiten (Grafana = Visualisierung, Mimir = Storage & Alerting).
- **Nachteile:**
  * Zusätzliche Komponenten-Abhängigkeit (Crossplane und der entsprechende Crossplane-Mimir-Provider).

### 2.3 Entscheidungsmatrix

| Aspekt | Variante A (Pur Grafana Operator) | Variante B (Hybrid via Crossplane) |
|---|---|---|
| **Zentrale Benachrichtigungs-Plane** | Grafana Alertmanager (intern) | Mimir Alertmanager (extern) |
| **Evaluierungs-Ort** | Grafana Alerting Engine | Mimir Ruler |
| **GitOps-Mechanismus** | Grafana Operator CRDs | Crossplane Mimir Provider CRDs |
| **Geeignet für** | Einfache, zentralisierte Umgebungen | Große Multi-Tenant- oder Cloud-Native-Plattformen |
| **Status in diesem Repo** | Archiviert/Möglich | **Aktiv & Implementiert** |

---

## 3. Alert Rules: Konzeption und Implementation

### 3.1 Alert-Domänen

| Domäne | Beispiele |
|---|---|
| Cluster Health | Node NotReady, Disk/Memory Pressure, Kubelet down, API-Server Error Rate, CrashLoopBackOff |
| GitOps / Argo CD | App OutOfSync, App Degraded, AppSet Generation Error, Repo-Server down |
| Kargo | Promotion Failed, Warehouse stale, Freight not verified, Stage unhealthy |
| Observability | Grafana down, Mimir Distributor/Ingester down, Ingestion Drop, Alloy Export Fehler |
| Infrastruktur | Crossplane Provider down, Managed Resource not Ready, Kyverno Webhook failures, Cert Renewal failed |
| Customer Workloads | Rollout stuck, HPA at Max, Quota > 90%, Pod Restarts |

**Rollout-Reihenfolge:** Observability → Cluster Health → Argo CD / Kargo → Zertifikate → Customer → Security

### 3.2 Label-Standard

#### Pflicht-Labels

| Label | Werte |
|---|---|
| `severity` | `critical` / `warning` / `info` |
| `service` | `kubernetes`, `argocd`, `kargo`, `crossplane`, `kyverno`, `mimir`, `grafana`, `otel` |
| `component` | `node`, `controller`, `api-server`, `ingester`, `deployment`, `promotion` |

#### Routing-Labels (empfohlen)

| Label | Werte |
|---|---|
| `domain` | `platform`, `gitops`, `devexperience`, `customer`, `observability`, `security` |
| `owner` | `S`, `GG`, `L`, `M`, `B`, `distribution` |
| `clusterTier` | `customer`, `non-customer` |
| `namespace` | Kubernetes-Namespace (aus Zeitreihen-Labels automatisch verfügbar) |
| `cluster` | Cluster-Identifier (von Alloy als `external_label` gesetzt) |

#### Pflicht-Annotations

- `summary` — Kurzbeschreibung
- `description` — Kontext und mögliche Ursache

#### Optionale Annotations

- `runbook_url`, `dashboard_uid`, `panel_id`

### 3.3 Label-Vererbung aus Zeitreihen

Wenn eine PromQL-Query Zeitreihen mit Labels zurückgibt, erbt jede Alert-Instanz diese Labels automatisch.
Routing auf diese Labels funktioniert ohne manuelle Konfiguration.

```text
kube_pod_info{namespace="customer-a", pod="my-pod"}
→ Alert hat automatisch: namespace=customer-a, pod=my-pod
→ Routing auf namespace=~"customer-a-.*" funktioniert
```

**Wichtig bei Aggregationen:** Labels gehen bei `count()`, `sum()` etc. verloren wenn `by(label)` fehlt.

| Label | Herkunft |
|---|---|
| `alertname` | Alert-Regel selbst |
| `namespace` | kube-state-metrics Zeitreihen-Label |
| `cluster` | Alloy external_label |
| `severity`, `service`, `owner`, `domain`, `clusterTier` | Statisch in Alert-Regel gesetzt |

### 3.4 Optionen für Standard-Alerts (Prometheus-Format → Grafana-Format)

Upstream-Mixins liefern Prometheus-Format. Grafana veröffentlicht keine fertigen Bundles (UID-Portabilitätsproblem).
Konvertierung ist einmalig erforderlich.

#### Option A: Mimir Ruler (abgelehnt)

Prometheus-Regeln direkt in Mimir Ruler laden — kein Konvertierungsaufwand.

**Abgelehnt:** Mimir Ruler hat keinen kompatiblen AM-Endpoint für Grafana Alertmanager (Abschnitt 2).

#### Option B: Import via Grafana-UI, dann exportieren

Prometheus-Regeln per UI importieren, als Grafana-managed Rules speichern, exportieren, versionieren.

**Nachteil:** UI-basierter Schritt; einmalig akzeptabel, nicht skalierbar.

#### Option C: Manuelle Konvertierung in `GrafanaAlertRuleGroup` YAML

Prometheus-Regeldatei manuell in `GrafanaAlertRuleGroup` CR umschreiben.

**Vorteil:** Volle Kontrolle, direkt GitOps-fähig.
**Nachteil:** Upstream-Updates müssen manuell nachgezogen werden.

#### Option D: Helm-Template-Konvertierung (empfohlen)

Helm-Template rendert Prometheus-Regeldateien on-the-fly in `GrafanaAlertRuleGroup` CRs.
Originaldateien bleiben im Prometheus-Format erhalten — portabel und als Referenz nutzbar.

```
apps/grafana/noctua/
├── files/
│   └── prometheus-rules/               # Prometheus-Format (Referenz, portabel)
│       ├── kubernetes-alerts.yaml
│       └── argocd-alerts.yaml
└── templates/
    └── grafana-alert-rule-groups.yaml  # Helm → GrafanaAlertRuleGroup CRs
```

```yaml
# values.yaml
grafana:
  mimirDatasourceUID: "mimir-prod-uid"   # Konstante — ändert sich nicht ohne Neuinstallation

# Helm-Template
- refId: A
  datasourceUid: {{ .Values.grafana.mimirDatasourceUID | quote }}
```

**Vorteil:** Originaldateien bleiben portabel; Konvertierung automatisiert.
**Nachteil:** Helm-Template-Komplexität; UID muss als Variable gepflegt werden.

> **Risiko:** Datasource-UID ändert sich bei Neuanlage der Grafana-Instanz. Alle `GrafanaAlertRuleGroup`
> Ressourcen müssen dann aktualisiert werden. UID als versionierte Konstante in `values.yaml` behandeln.

### 3.5 GitOps-Workflow Alert Rules

```text
1. GrafanaAlertRuleGroup CR anlegen
   → manuell oder via Helm-Template aus Prometheus-Regeldatei
   → Ablegen in apps/grafana/noctua/files/alert-rules/ oder als Template

2. PR mit: Query, Labels, Annotations, Runbook-Kontext

3. Merge → Argo CD sync → Grafana Operator reconcile → Grafana

4. Validierung:
   → kubectl get grafanaalertrulegroup -n grafana (Status prüfen)
   → Grafana UI: Alerting → Alert Rules
```

### 3.6 Definition of Done (pro Regel)

- [ ] Query fachlich validiert
- [ ] `severity`, `service`, `component` gesetzt
- [ ] `owner` und `domain` gesetzt (Routing-relevant)
- [ ] `summary` und `description` vorhanden
- [ ] Firing und Resolve getestet
- [ ] Empfängerpfad verifiziert

---

## 4. Notification Policy & Contact Points

### 4.1 Infra-Team Routing (Plattform-eigene Alerts)

Routing basiert auf Labels, die in den Alert Rules statisch gesetzt werden.
Grafana Alertmanager v2 — Routing identisch zu Prometheus Alertmanager.

#### Routing-Matrix

| Bereich | Verantwortlich | Route-Matcher | Empfänger |
|---|---|---|---|
| DevExperience | S | `owner=S` | S-direkt + devex-verteiler + devex-teams |
| GitOps / Argo CD / Kargo | GG | `service=argocd` oder `service=kargo` | GG-direkt + gitops-verteiler + gitops-teams |
| Crossplane | L | `service=crossplane` | L-direkt + infra-verteiler + infra-teams |
| Kyverno | Verteiler | `service=kyverno` | kyverno-verteiler + security-teams |
| Customer-Cluster | M | `clusterTier=customer` | M-direkt + customer-verteiler + customer-teams |
| Non-Customer-Cluster | B | `clusterTier=non-customer` | B-direkt + platform-verteiler + platform-teams |
| Fallback | — | — | platform-all |

#### Ziel-Routing-Struktur

```text
Root Policy (receiver: platform-all)
├── service=argocd OR service=kargo  → GG + gitops-verteiler + gitops-teams
├── owner=S                          → S + devex-verteiler + devex-teams
├── service=crossplane               → L + infra-verteiler + infra-teams
├── service=kyverno                  → kyverno-verteiler + security-teams
├── clusterTier=customer
│   ├── namespace=~customer-a-.*    → customer-a-contact-point     ← Customer-eigener CP
│   ├── namespace=~customer-b-.*    → customer-b-contact-point
│   └── fallback                    → M + customer-verteiler + customer-teams
├── clusterTier=non-customer         → B + platform-verteiler + platform-teams
└── fallback                         → platform-all
```

#### Severity-Intervalle

| Severity | group_wait | group_interval | repeat_interval |
|---|---|---|---|
| `critical` | 30s | 5m | 30m |
| `warning` | 2m | 15m | 4h |
| `info` | 5m | 1h | 24h |

**Fallback-Pflicht:** Jede Route braucht eine Fallback-Route auf `platform-all`. Kein Alert ohne Empfänger.

### 4.2 GitOps-Implementierung

Contact Points und Notification Policies werden ausschliesslich via Grafana Operator deployed.
Manuelle UI-Änderungen werden von Argo CD überschrieben.

```text
apps/grafana/noctua/templates/
├── grafana-operator-contactpoints.yaml         # GrafanaContactPoint CRs
└── grafana-operator-notification-policies.yaml # GrafanaNotificationPolicy CR
```

```yaml
# GrafanaContactPoint Beispiel
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaContactPoint
metadata:
  name: gitops-team-gg
spec:
  instanceSelector:
    matchLabels:
      dashboards: "grafana"
  name: gitops-team-gg
  type: email
  settings:
    addresses: "gg@company.com;gitops-verteiler@company.com"
```

```text
Workflow:
1. GrafanaContactPoint / GrafanaNotificationPolicy CR bearbeiten
2. PR → Merge
3. Argo CD sync → Grafana Operator reconcile → Grafana Alertmanager
```

### 4.3 Optionen für Notification-Konfiguration (evaluiert)

#### Option A: Mimir Alertmanager + mimirtool-Job (abgelehnt)

Job liest ConfigMap mit AM-Konfiguration und pusht via `mimirtool rules load`.

**Abgelehnt:** Eigene Controller-Komponente nötig; Mimir AM per Grafana Operator nicht konfigurierbar.

#### Option B: Crossplane Mimir Provider (abgelehnt)

Community-Port des Terraform-Providers; verwaltet Mimir AM Konfiguration als CR.

**Abgelehnt:** Inoffiziell, nicht supported; splitted Dependencies zu Grafana Operator.

#### Option C: Grafana Operator CRs auf internen AM (gewählt)

`GrafanaContactPoint` + `GrafanaNotificationPolicy` CRs via Grafana Operator.

**Warum:** Einzige vollständig GitOps-fähige Option; keine zusätzliche Dependency.

---

## 5. Self-Service: Customer Alert Rules & Routing

### 5.1 Überblick

Kunden deployen Alert Rules aus ihrem eigenen GitOps-Repository.
Der Grafana Operator picked CRs aus beliebigen Namespaces auf (via `instanceSelector`).
Notification Routing wird vom Plattform-Team verwaltet und ergänzt die zentrale Policy.

```text
Customer-GitOps-Repo
  └── namespaces/customer-a/
      ├── grafana-folder.yaml            # GrafanaFolder CR
      ├── grafana-alert-rule-group.yaml  # GrafanaAlertRuleGroup CR
      └── grafana-contact-point.yaml     # GrafanaContactPoint CR (optional)

Grafana Operator (im Plattform-Cluster)
  → watched namespace: customer-a-namespace
  → picked up CRs mit instanceSelector: dashboards=grafana
  → provisioniert in zentraler Grafana-Instanz

Plattform-Repo
  └── apps/grafana/noctua/templates/
      └── grafana-operator-notification-policies.yaml
          → Route für namespace=~"customer-a-.*" ergänzt
```

### 5.2 Was Kunden selbst deployen können

#### GrafanaAlertRuleGroup (Customer-Namespace)

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaAlertRuleGroup
metadata:
  name: customer-a-app-alerts
  namespace: customer-a-namespace
spec:
  instanceSelector:
    matchLabels:
      dashboards: "grafana"
  folderRef: customer-a-folder
  rules:
    - uid: customer-a-pod-restarts
      title: "Pod Restarts > 5/h"
      condition: B
      data:
        - refId: A
          datasourceUid: "<mimir-datasource-uid>"   # Konstante, vom Plattform-Team dokumentiert
          model:
            expr: 'increase(kube_pod_container_status_restarts_total{namespace="customer-a-namespace"}[1h])'
        - refId: B
          datasourceUid: "__expr__"
          model:
            type: threshold
            conditions:
              - evaluator: { params: [5], type: gt }
      for: 0s
      labels:
        severity: warning
        owner: customer-a
        namespace: customer-a-namespace   # Für Routing nutzbar
```

#### GrafanaContactPoint (Customer-Namespace, optional)

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaContactPoint
metadata:
  name: customer-a-email
  namespace: customer-a-namespace
spec:
  instanceSelector:
    matchLabels:
      dashboards: "grafana"
  name: customer-a-email
  type: email
  settings:
    addresses: "team@customer-a.com"
```

### 5.3 Was Kunden nicht selbst deployen können

- `GrafanaNotificationPolicy` — greift auf zentrale Routing-Konfiguration zu, muss Plattform-owned bleiben
- Contact Points anderer Kunden referenzieren
- Labels aus fremden Namespaces matchen

### 5.4 Dynamisches & wartungsfreies Customer Routing (Self-Service)

Da die Alertmanager-Konfiguration von Mimir monolithisch ist und eine manuelle Pflege von Routen pro Kunde einen hohen Wartungsaufwand bedeutet, nutzen wir dynamische Routing-Strategien, um echten Self-Service ohne manuelle GitOps-Änderungen an der zentralen Policy zu ermöglichen.

#### Strategie A: Dynamisches Go-Template Routing (Für neue Rules)

Wenn Kunden neue Prometheus-Rules deployen, können sie die Empfänger-E-Mails direkt als Label an der Alert-Rule definieren. 

1. **Die Prometheus-Rule des Kunden:**
   Der Kunde fügt das Label `email_to` hinzu (unterstützt auch kommagetrennte Listen für mehrere Empfänger):
   ```yaml
   labels:
     severity: critical
     email_to: "saadmasood@web.de, team-alerts@company.com"
   ```

2. **Das Mimir-Alertmanager-Routing (Zentral):**
   Die zentrale Notification Policy gruppiert nach `email_to` und nutzt ein Go-Template zur dynamischen Auflösung des Empfängers zur Laufzeit:
   ```yaml
   route:
     receiver: dynamic-email-receiver
     groupBy: [alertname, namespace, email_to]
   receiver:
     - name: dynamic-email-receiver
       emailConfigs:
         - to: '{{ if .GroupLabels.email_to }}{{ .GroupLabels.email_to }}{{ else if .GroupLabels.namespace }}{{ .GroupLabels.namespace }}@web.de{{ else }}admin-fallback@web.de{{ end }}'
   ```
   *Vorteil:* Komplett dynamisch. Der neue Kunde deployed seine Rule und erhält sofort E-Mails über den zentralen SMTP-Server, ohne dass das Plattform-Team etwas anpassen muss.

#### Strategie B: Namespace-basiertes Webhook-Forwarding (Für vorhandene Rules)

Bei bereits vorhandenen Rules (z. B. Upstream-Mixins für Kubernetes/Argo CD) können wir das `email_to`-Label nicht nachträglich in die Regeln einbringen. Hier nutzen wir einen **Webhook-Forwarder-Proxy**:

1. **Der Datenfluss:**
   ```text
   Alert (namespace="customer-a") → Mimir Alertmanager 
   → Webhook Receiver (zentraler Forwarder-Dienst)
   → Forwarder liest "namespace"-Label aus
   → Forwarder sucht ConfigMap "alert-recipients" im Namespace "customer-a"
   → Forwarder liest E-Mail-Adressen und sendet E-Mail
   ```

2. **Das Customer-Manifest (Self-Service im eigenen Namespace):**
   Jeder Kunde legt in seinem Namespace eine einfache ConfigMap mit seinen E-Mail-Adressen an. Da Benutzer nur Zugriff auf ihren eigenen Namespace haben, ist dies vollkommen isoliert:
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: alert-recipients
     namespace: customer-a
   data:
     emails: "saadmasood@web.de, another@domain.com"
   ```

3. **Der Vorteil:**
   Die zentrale Notification Policy leitet einfach jeden Alert an den Webhook-Dienst weiter. Dieser löst die Empfänger dynamisch über die Kubernetes-API auf. Es müssen keine Secrets oder E-Mail-Listen im Plattform-Repo gepflegt werden.

#### 5.4.3 Vergleich & Analyse: Monolithisches Mimir vs. Grafana Operator

Hier analysieren wir das Problem der dezentralen Konfiguration bei beiden Ansätzen:

##### 1. Mimir / Prometheus Alertmanager (Crossplane-managed)
Bei Mimir's nativem Alertmanager gibt es **keinen** Operator, der einzelne Routing-CRDs mergt. Die Alertmanager-Konfiguration ist zwingend ein **Monolith** pro Tenant (in unserem Fall Tenant `1`).
* **Das Problem:** Kunden können keine eigenen Notification Policies oder Routing-Bäume deployen. Jede Änderung erfordert das Editieren des monolithischen Mimir-Alertmanager-Manifests (z. B. im Plattform-Repo).
* **Die Lösung:**
  * **Für neue Rules:** `email_to` Go-Template Strategie (Strategie A). Hier spart man sich jegliche Notification Policy Definition im Plattform-Repo.
  * **Für vorhandene/Upstream-Rules (z. B. Mixins ohne `email_to` Label):** Webhook-Forwarder-Proxy (Strategie B). Der Proxy sucht die ConfigMap `alert-recipients` im jeweiligen Target-Namespace (den er aus dem Alert-Label `namespace` ausliest). Somit bleibt das Mimir-Manifest statisch und Kunden steuern die Empfänger komplett dynamisch via ConfigMap in ihrem Namespace.

##### 2. Grafana Alertmanager (Grafana Operator-managed)
Gibt es dieses Monolithen-Problem auch beim Grafana Operator? **Nein, hier ist das gelöst!**
* **Wie es funktioniert:** Der Grafana Operator unterstützt neben der Haupt-`GrafanaNotificationPolicy` auch die Namespaced CRDs `GrafanaNotificationPolicyRoute` und `GrafanaContactPoint`.
* **Self-Service Ablauf:**
  1. Der Kunde deployed in seinem Namespace einen eigenen `GrafanaContactPoint` und eine `GrafanaNotificationPolicyRoute`.
  2. Die Route referenziert seinen Contact Point und matched nur auf Alerts aus seinem Namespace (`namespace = "customer-a"`).
  3. In der zentralen `GrafanaNotificationPolicy` der Plattform wird ein `routeSelector` definiert (z. B. `matchLabels: type: customer-route`).
  4. Der Grafana Operator sammelt alle passenden `GrafanaNotificationPolicyRoute` CRDs clusterweit ein und baut die finale, hierarchische Routing-Tree-Struktur in Grafana dynamisch zusammen.
* **Vorteil:** Volle GitOps-Dekopplung. Neue Kunden können eigenständig neue Benachrichtigungswege definieren, ohne das Plattform-Repository zu berühren.

#### 5.4.4 Mandanten-Föderation: Separater Tenant für Alerting & Routing

Wenn die Ingestion (die Metrik-Daten) vollständig über einen einzigen Mandanten (z. B. `anonymous` oder `1`) läuft, können wir dennoch **vollständig isolierte Rules und Routing-Policies für neue Kunden** in separaten Tenants definieren. Dies geschieht über die native **Mimir Tenant Federation (Cross-Tenant Querying / Federated Rule Groups)**.

##### 1. Funktionsweise & Datenfluss
```text
[ Metrics Ingestion ]
          │
          ▼
    Tenant: "anonymous" (Enthält alle Metrik-Zeitreihen)

[ Rule Evaluation ]
    Tenant: "tenant-b" (Eigener Kunden-Tenant für Alerts)
          │
          ├─► Mimir Ruler (tenant-b) führt Rule-Query aus
          │   mit "source_tenants: [anonymous]"
          │
          ├─► Query liest Daten aus dem "anonymous" Backend
          │
          ├─► Firing Alert wird unter "tenant-b" erzeugt
          │
          ▼
[ Notification Routing ]
    Tenant: "tenant-b" Alertmanager
          │
          ▼
    Nutzt die isolierte Alertmanager-Config von "tenant-b"
```

##### 2. Benötigte Konfiguration in Mimir (Infrastruktur)
Um dieses Feature freizuschalten, müssen in Mimir die entsprechenden Feature-Flags aktiviert werden (z. B. in den Helm `values.yaml` oder CLI-Argumenten für Ruler, Querier und Query-Frontend):
```yaml
mimir:
  config:
    limits:
      tenant_federation:
        enabled: true  # Erlaubt Querier/Query-Frontend mandantenübergreifende Abfragen
    ruler:
      tenant_federation:
        enabled: true  # Erlaubt dem Ruler die Auswertung von source_tenants
```
*(CLI-Flags: `-tenant-federation.enabled=true` und `-ruler.tenant-federation.enabled=true`)*

##### 3. Definition der Ressourcen via Crossplane

* **Alerting Rule für den Kunden-Tenant (`orgId: tenant-b`):**
  Die Rules werden dem neuen Tenant zugewiesen, greifen aber über `source_tenants` auf die Metriken von `anonymous` zu.
  ```yaml
  apiVersion: ruler.mimir.crossplane.io/v1alpha1
  kind: Rules
  metadata:
    name: tenant-b-alerts
  spec:
    forProvider:
      orgId: "tenant-b"  # Der Tenant, der den Alert erzeugt
      namespace: "customer-alerts"
      content: |
        groups:
          - name: kubernetes-alerts
            source_tenants:
              - "anonymous"  # Holt sich die Daten aus dem anonymous-Tenant
            rules:
              - alert: PodDown
                expr: up{job="kube-state-metrics"} == 0
                for: 5m
                labels:
                  severity: critical
  ```

* **Alertmanager Config für den Kunden-Tenant (`orgId: tenant-b`):**
  Diese Konfiguration ist für andere Mandanten komplett unsichtbar und isoliert.
  ```yaml
  apiVersion: alertmanager.mimir.crossplane.io/v1alpha1
  kind: Config
  metadata:
    name: tenant-b-alertmanager-config
  spec:
    forProvider:
      orgId: "tenant-b"  # Isoliert die Routing-Richtlinien komplett für tenant-b
      route:
        - receiver: tenant-b-email
          matchers:
            - severity = critical
      receiver:
        - name: tenant-b-email
          emailConfigs:
            - to: "saadmasood@web.de"
  ```

##### 4. Bewertung
* **Vorteil:** Maximale Isolation. Neue Kunden erhalten eigene Rule- und Notification-Ressourcen, die sie selbst (oder das GitOps-System) deklarieren können, ohne die globale Konfiguration zu beeinträchtigen. Die Ingestion muss nicht aufgesplittet werden.
* **Keine manuelle Mandantenregistrierung nötig:** Grafana Mimir verwaltet Mandanten (Tenants) vollständig dynamisch. Es gibt keine Datenbank oder Registrierungs-API, um Tenants anzulegen. Der Tenant `tenant-b` existiert automatisch in dem Moment, in dem die erste Rule oder Alertmanager-Konfiguration mit dem HTTP-Header `X-Scope-OrgID: tenant-b` (oder dem Crossplane-Feld `orgId: tenant-b`) an die Mimir-API gesendet wird. Mimir legt die entsprechenden Pfade im Storage-Backend on-the-fly an.
* **Einschränkung:** Erfordert die Aktivierung der Tenant-Federation in der Mimir-Cluster-Konfiguration.

### 5.5 Ownership-Modell

| Alert-Typ | Regelquelle | Routing-Verantwortung | Notification-Plane |
|---|---|---|---|
| Plattform-Alerts | Plattform-Repo | Plattform | Grafana Alertmanager (intern) |
| Customer-App-Alerts | Customer-Repo | Plattform (ergänzt Route) + Kunde (Contact Point) | Grafana Alertmanager (intern) |
| Plattform-Alerts mit Customer-Auswirkung | Plattform-Repo | Plattform (Namespace-Routing) | Grafana Alertmanager (intern) |

Genau eine Notification-Plane für alle Alert-Typen.

### 5.6 Constraints und offene Punkte

| Constraint / Punkt | Details |
|---|---|
| Editor-User können Notification Policies nicht per UI ändern | Nur read-only; Routing läuft via GitOps |
| Plattform muss pro Customer eine Route manuell hinzufügen | Kein automatisches Self-Service für Routing; Automatisierung mittelfristig möglich |
| Datasource-UID muss dem Kunden bekannt sein | Als Konstante in Plattform-Doku / values.yaml pflegen |
| Multi-Cluster-Routing (mehrere Cust-Cluster) | Noch nicht abgebildet |

---

## 6. Offene Punkte

| Punkt | Status |
|---|---|
| Standard-Alerts (Kubernetes, Argo CD) via Helm-Template konvertieren | Offen |
| Echte Contact Points für alle Infra-Team-Empfänger hinterlegen | Offen |
| Zentrale Notification Policy mit vollständiger Routing-Matrix deployen | Offen |
| Datasource-UID als Konstante in `values.yaml` dokumentieren | Offen |
| Multi-Cluster-Routing (mehrere Cust-Cluster) | Später |
| Runbook-Links pro Kernalert | Mittelfristig |
| Automatisches Customer-Routing (kein manuelles PR pro Kunde) | Mittelfristig |

---

## 7. Leitlinie

- Grafana-managed Alert Rules sind die einzige primäre Regelquelle.
- Grafana Alertmanager (intern) ist die einzige primäre Notification-Plane.
- Mimir Ruler nicht für produktive Alert-Regeln (technischer Blocker, Abschnitt 2).
- Mimir Alertmanager nicht als Notification-Plane (Grafana Operator API fehlt, Abschnitt 2).
- UI-Änderungen an Contact Points und Policies sind nicht persistent — nur GitOps zählt.
- Editor-User können Notification Policies und Contact Points nur lesen, nicht schreiben.
- Tenant `1` ist Standard für alle Mimir-Queries.

---

## 8. Referenzen

- `docs/alerting/alerting-plan.md` — Alert-Regelkatalog mit PromQL-Queries
- `docs/observability/OBSERVABILITY.md`
- `docs/observability/MIMIR.md`
- `apps/grafana/noctua/values.yaml`
- `apps/grafana/noctua/templates/`
- `apps/crossplane/noctua/templates/mimir-alertmanager-config.yaml` — Test-Telegram-Receiver

---

## Anhang A: Archiv — Alte Architektur (Mimir Ruler + Mimir Alertmanager)

> **Archiv:** Dokumentiert die ursprünglich geplante Hybrid-Architektur. Abgelöst durch Abschnitt 2.
> Bleibt als Referenz erhalten, falls sich die technischen Constraints ändern.

### A.1 Geplantes Hybrid-Modell

- **Pfad A:** Mimir Ruler evaluiert Prometheus-Regeln → Mimir Alertmanager
- **Pfad B:** Grafana-managed Alerts → weitergeleitet an Mimir Alertmanager als externe Plane

Ziel: Mimir Alertmanager als zentrale Notification-Plane für beide Alert-Typen.

### A.2 Mimir Ruler

```text
Prometheus-Regeln → mimirtool rules load → Mimir API (Tenant 1)
→ Mimir Ruler evaluiert PromQL → Alert firing
→ Mimir Ruler → Alertmanager-Endpoint (nur Mimir AM)
```

### A.3 GitOps-Mechanismus: Checksum-basierter Sync-Job

Kubernetes-Jobs sind immutable (Name + Selector nach Erstellung unveränderbar). Lösung: Name-Rotation via Checksum.

```text
1. Regeldateien: apps/mimir/prod/files/**/alerts*.yaml
2. Helm-Template bündelt alle in ConfigMap: mimir-rules-bundle
3. Job: mimir-rules-sync-<checksum>
4. Checksum = Hash(Regeldateien + Mimir-Infrastruktur-Config)
5. Änderung → neue Checksum → neuer Job → Argo CD erstellt ihn → mimirtool pusht Regeln
```

**Doppelte Checksum:** Mimir Ruler nutzt `emptyDir` — bei Pod-Neustart gehen Regeln verloren.
Infrastruktur-Änderungen (Memory-Limits etc.) triggern Pod-Neustart. Checksum-Kopplung stellt sicher,
dass Sync-Job nach jedem Ruler-Neustart erneut läuft.

**Archivierte Dateien:**

```
apps/mimir/prod/
├── files/mimir/alerts.yaml               # Prometheus-Format (Referenz, behalten)
└── templates/
    ├── ruler-rules-configmap.yaml         # Obsolet
    └── ruler-rules-sync.yaml             # Obsolet
```

### A.4 Mimir Alertmanager

Prometheus-kompatibler Alertmanager als Teil von Mimir. Konfiguration tenant-spezifisch via API.

**Evaluierte Deployment-Optionen:**

| Option | Mechanismus | Warum abgelehnt |
|---|---|---|
| mimirtool CLI-Job | Job liest ConfigMap, pusht via Mimir API | Eigene Controller-Komponente; Split-Dependencies |
| Crossplane Mimir Provider | Community-Port des Terraform-Providers | Inoffiziell, nicht supported |
| Grafana Operator | `GrafanaNotificationPolicy` CR | Greift nur auf internen Grafana AM zu — nicht Mimir AM |

### A.5 Warum das Hybrid-Modell nicht funktioniert

```
Problem 1: Grafana Operator → Mimir Alertmanager
  GrafanaNotificationPolicy CR
    → Grafana Internal API (/api/alertmanager/grafana/...)
    → Interner Grafana Alertmanager
  Mimir Alertmanager
    → Eigene API (/api/v1/alerts)
    → KEIN Zugriff via Grafana Operator
  GitHub Issue > 1 Jahr offen.

Problem 2: Mimir Ruler → Grafana Alertmanager
  Mimir Ruler sendet Alerts nur an konfigurierten alertmanager_url.
  Grafana Alertmanager ist kein offiziell supported Ziel. Kompatibilität nicht garantiert.

Problem 3: Split-Dependencies
  Dashboards: Grafana Operator
  Alert-Regeln: Mimir Ruler via mimirtool-Job
  Notification Config: Crossplane Provider oder eigener Controller
  → Drei verschiedene Sync-Mechanismen mit je eigenen Fehlerquellen.
```

### A.6 Datei-Status

| Datei / Komponente | Status |
|---|---|
| `apps/mimir/prod/files/**/alerts*.yaml` | Behalten — portable Prometheus-Referenz |
| `apps/mimir/prod/templates/ruler-rules-configmap.yaml` | Obsolet |
| `apps/mimir/prod/templates/ruler-rules-sync.yaml` | Obsolet |
| `apps/crossplane/noctua/templates/mimir-alertmanager-config.yaml` | Aktiv (Test-Telegram-Receiver) |
| Mimir Ruler Deployment | Passiv — läuft, keine Regeln geladen |
| Mimir Alertmanager | Passiv — minimale Fallback-Konfiguration |

### A.7 Wann könnte Hybrid wieder relevant werden?

1. Grafana Operator bekommt Support für externe Alertmanager in `GrafanaNotificationPolicy`.
2. Offizieller, supported Crossplane Mimir Provider verfügbar.
3. Mandatorische Tenant-Isolation pro Kunde nötig (Mimir AM unterstützt Tenant-Isolation nativ, Grafana AM nicht).
4. Upstream-Prometheus-Mixins direkt ohne Konvertierung einsetzen.

---

## Anhang B: Technischer PoC — Provisionierung mit Crossplane

Im Rahmen eines technischen PoC wurde die deklarative Bereitstellung von Alerting Rules und Recording Rules via Crossplane untersucht und erfolgreich implementiert.

### B.1 Geplante Struktur & Ablauf

Die Provisionierung nutzt den Crossplane Mimir Provider (`rules.ruler.mimir.crossplane.io`) zur direkten Interaktion mit der Mimir Ruler HTTP API.

```text
Argo CD (GitOps) -> Crossplane Rules CR (noctua namespace)
                 -> Reconcile Loop (Crossplane Provider-Mimir)
                 -> Mimir Ruler HTTP API (SetRuleGroup API)
                 -> Writes to filesystem backend (/rules-storage)
                 -> Mimir Ruler evaluates rules
```

Dabei werden die bestehenden Rohdateien unter `apps/crossplane/noctua/files/` importiert und automatisch als Crossplane `Rules` Manifeste gerendert.

### B.2 Aufgetretene Probleme und Lösungen

Während der Implementierung des PoC traten zwei wesentliche Probleme auf:

#### 1. Mimir Ruler Schreibfehler (`read-only file system`)
- **Problem:** Das Standard-Deployment des Mimir Rulers lief mit `readOnlyRootFilesystem: true`. Da Mimir Ruler bei Nutzung des `filesystem`-Speicherbackends unter dem Pfad `/rules-storage` versuchen muss, Regeldateien zu schreiben, stürzte der Pod mit der Fehlermeldung `mkdir /rules-storage: read-only file system` ab.
- **Lösung:** In `apps/mimir/noctua/values.yaml` wurde das nicht vom Upstream-Chart unterstützte Feld `persistentVolume` entfernt. Stattdessen wurde über `extraVolumes` und `extraVolumeMounts` ein schreibbares `emptyDir`-Volume mit dem Namen `rules-storage` gemountet:
  ```yaml
  extraVolumes:
    - name: rules-storage
      emptyDir: {}
  extraVolumeMounts:
    - name: rules-storage
      mountPath: /rules-storage
  ```
  Da Crossplane den Zustand kontinuierlich vergleicht, führt ein Pod-Neustart (und damit das Leeren des `emptyDir`) nicht zum permanenten Verlust der Regeln, da Crossplane diese automatisch neu per API anlegt.

#### 2. Ungültiges Dateiformat bei `PrometheusRule` CRs
- **Problem:** Ein Teil der Regeldateien (z.B. für Kubernetes-Infrastruktur wie `grafana-prometheusRule.yaml`) lag im Kubernetes `PrometheusRule`-Custom-Resource-Format (von `monitoring.coreos.com/v1`) vor. Mimir's Ruler API erwartet jedoch rohes Prometheus Rule-Group-YAML (beginnend mit `groups:` auf Root-Ebene). Dies führte bei Crossplane zu Validierungsfehlern (`content validation failed: at least one rule group is required`).
- **Lösung:** Im Helm-Template `apps/crossplane/noctua/templates/mimir-ruler-rules.yaml` wurde eine automatische Konvertierung eingebaut. Mithilfe der Helm-Funktion `fromYaml` wird geprüft, ob die Datei ein Kubernetes Custom Resource Format mit `.spec.groups` besitzt. Falls ja, wird dieses extrahiert und on-the-fly in das rohe Prometheus Rule-Format umgewandelt:
  ```yaml
  {{- $yaml := $fileContent | fromYaml }}
  {{- if and $yaml.spec $yaml.spec.groups }}
  groups:
  {{- toYaml $yaml.spec.groups | nindent 6 }}
  {{- else }}
  {{- $fileContent | nindent 6 }}
  {{- end }}
  ```

### B.3 Validierung und Status

Nach dem Einspielen der Fixes wurden 17 `Rules` CRs erfolgreich synchronisiert. Die Abfrage der internen Mimir Ruler API ergab, dass alle 74 Regelgruppen (inklusive der dynamisch konvertierten Kubernetes-Regeln) geladen wurden und evaluiert werden.

