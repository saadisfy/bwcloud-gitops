# Step-by-Step Anleitung: Migration von ConfigMap-basierten Mimir-Rules auf Crossplane Provisionierung

Diese Anleitung richtet sich an Junior-Engineers und Einsteiger. Sie beschreibt Schritt für Schritt, wie man eine bestehende, ConfigMap-basierte Rule-Synchronisation in Grafana Mimir auf eine moderne, API-gestützte Bereitstellung mittels **Crossplane** umstellt.

Zusätzlich ist hier das technische Zielbild aus der `dev-observability`-Umgebung eingearbeitet: Metriken werden über **Grafana Alloy** nach Mimir gesendet, Rules werden sauber nach Plattform- und Applikations-Alerting getrennt, und Alert-Routing wird bewusst entweder über den Mimir Alertmanager oder den Grafana Alertmanager betrieben.

---

## 📋 Ausgangslage
* **Crossplane** ist bereits im Kubernetes-Cluster installiert.
* **Mimir** ist installiert und speichert seine TSDB-Blöcke bereits erfolgreich in S3/MinIO.
* **Der Mimir Ruler** läuft aktuell mit dem Backend `local` und lädt seine Regeln über ein ConfigMap-Volume-Mount unter `/rules-storage`.
* **Ziel:** Die Regeln sowie die Benachrichtigungskanäle (Alertmanager Config) sollen stattdessen über Crossplane provisioniert werden.

---

## 🧭 Zielbild und wichtige Entscheidungen vor der Umsetzung

Bevor Dateien geändert werden, müssen die folgenden Punkte einmal bewusst festgelegt werden. Das verhindert später typische Fehler wie falsche Tenants, nicht geladene Rules oder Alertmanager-Routing ins Leere.

### A. Datenfluss für Metriken
Der gewünschte Datenfluss ist:

```text
Kubernetes / ServiceMonitor / cAdvisor / kube-state-metrics
  -> Grafana Alloy
  -> OTLP HTTP Exporter
  -> Mimir Distributor
  -> Mimir Storage
  -> Mimir Ruler
  -> Alertmanager
```

Wichtig ist dabei, dass **Alloy**, **Crossplane ProviderConfig**, **Mimir Ruler Rules** und **Alertmanager Config** denselben Tenant verwenden. In diesem Repository ist der Tenant in den Beispielen aktuell `1`. In der DZ-Dev-Referenz war der Tenant `anonymous`.

| Thema | DZ-Dev-Referenz | Dieses Repository / Beispiel |
|---|---|---|
| Kubernetes-Kontext | GKE `dev-observability` | aktueller Cluster / Environment |
| Mimir Tenant | `anonymous` | `1` |
| Alloy Export | externer/preleng Mimir Endpoint | interner Mimir Distributor |
| Storage | GCS mit Workload Identity | S3/MinIO oder environment-spezifisch |
| Rule-Bereitstellung bisher | ConfigMap nach `/rules-storage/<tenant>` | ConfigMap oder lokaler Sync |
| Ziel | deklarative/API-basierte Rules | Crossplane `Rules` CRs |

### B. Zwei Arten von Alerting sauber trennen

Es gibt zwei unterschiedliche Ebenen. Diese sollten nicht vermischt werden:

1. **Plattform-Alerting über Mimir Ruler**
  * Beispiele: Mimir, Loki, Tempo, Alloy, Kubernetes Nodes, Kubelet, Gatekeeper.
  * Format: Prometheus Rule Groups in YAML.
  * Ziel der Migration: Verwaltung über Crossplane `rules.ruler.mimir.crossplane.io`.

2. **Applikations-Alerting über Grafana Operator**
  * Beispiele: App-spezifische Alerts wie `spring-petclinic` oder Demo-Apps.
  * Format: `GrafanaAlertRuleGroup` oder vom Grafana Operator unterstützte Alert-Ressourcen.
  * Diese Alerts werden nicht zwingend in Mimir Ruler migriert, sondern können weiter über Grafana laufen.

**Faustregel:** Alles, was clusterweit und plattformnah ist, gehört in Mimir Ruler. Alles, was App-Teams selbst besitzen und in Grafana verwalten sollen, gehört in Grafana Operator CRDs.

### C. Alertmanager-Ziel bewusst wählen

Für die Benachrichtigung gibt es zwei saubere Varianten:

1. **Mimir Alertmanager verwenden**
  * Crossplane verwaltet zusätzlich `configs.alertmanager.mimir.crossplane.io`.
  * Der Ruler sendet an den Mimir Alertmanager, z. B. `http://mimir-alertmanager.mimir.svc.cluster.local:8080/alertmanager`.
  * Gut, wenn Alerting komplett Mimir-zentriert bleiben soll.

2. **Grafana Alertmanager verwenden**
  * Grafana Operator verwaltet `GrafanaContactPoint` und `GrafanaNotificationPolicy`.
  * Der Mimir Ruler sendet an Grafana, z. B. `http://grafana.<namespace>.svc.cluster.local/api/alertmanager/grafana`.
  * Gut, wenn Routing, Contact Points und Policies bereits deklarativ über den Grafana Operator gepflegt werden.

**Wichtig:** Nicht beide Varianten halb konfigurieren. Für diese Anleitung wird zunächst Variante 1 beschrieben. Wenn Grafana Alertmanager genutzt werden soll, muss Schritt 5 durch Grafana Operator Contact Points und Notification Policies ersetzt werden.

### D. Die `structuredConfig`-Falle

Beim Mimir Helm Chart ist `structuredConfig` sehr mächtig, aber gefährlich: Wird ein Block wie `ruler:` überschrieben, gehen Chart-Defaults oder automatisch generierte interne Adressen verloren, wenn sie nicht explizit erneut gesetzt werden.

Daher bei jeder Änderung am `structuredConfig`-Block prüfen:

* Ist `ruler.alertmanager_url` korrekt gesetzt?
* Ist `ruler_storage.backend` korrekt gesetzt?
* Ist der Storage-Pfad schreibbar?
* Ist der Tenant konsistent mit `X-Scope-OrgID`?
* Sind Basic Auth, Header oder TLS-Einstellungen nötig?

### E. Was hier noch sauberer und detaillierter umgesetzt werden muss

Diese Punkte sind die eigentliche To-do-Liste für eine robuste Umsetzung:

- [ ] Tenant-ID zentral in `values.yaml` definieren und nicht im Template hart codieren.
- [ ] Mimir Endpoint zentral in `values.yaml` definieren.
- [ ] Rule-Dateien zentral als Liste in `values.yaml` pflegen.
- [ ] Alertmanager-Variante explizit entscheiden: Mimir Alertmanager **oder** Grafana Alertmanager.
- [ ] Plattform-Alerts und Applikations-Alerts in getrennten Ordnern halten.
- [ ] PrometheusRule-CRDs beim Rendern zuverlässig in rohes Prometheus-Rule-Format konvertieren.
- [ ] Helm-Render-Test als Pflichtvalidierung vor jedem Merge ausführen.
- [ ] Argo CD Sync-Waves so setzen, dass Provider und CRDs vor den `Rules`-Objekten existieren.
- [ ] Nach Deployment immer Crossplane-Status, Mimir Ruler API und Alertmanager-Status prüfen.

---

## 🛠️ Schritt 1: Mimir-Konfiguration anpassen (Schreibrechte & API aktivieren)

Weil Crossplane die Regeln über die HTTP-API in den Ruler schiebt, benötigt der Ruler Schreibrechte. Da der Container standardmäßig mit einem read-only Filesystem läuft, müssen wir ein beschriebenes Verzeichnis bereitstellen.

### 1.1 Mimir Values editieren
Öffne die Datei `apps/mimir/noctua/values.yaml` (oder die entsprechende Datei für dein Environment `dev/values.yaml`) und passe den `ruler`-Bereich an:

1. Ändere das `ruler_storage.backend` von `local` auf `filesystem`.
2. Entferne den alten `persistentVolume`-Block unter `ruler` (dieser wird vom Upstream-Chart oft ignoriert) und erstelle stattdessen ein `emptyDir`-Volume via `extraVolumes` und `extraVolumeMounts`.
3. Deaktiviere das alte ConfigMap-Sync-Skript (`rulerRuleSync.enabled: false`).

Passe deine `values.yaml` wie folgt an:

```yaml
mimir-distributed:
  mimir:
    structuredConfig:
      ruler:
        # Pfad für die temporäre Auswertung der Regeln
        rule_path: /data/ruler-rules
        alertmanager_url: "http://mimir-alertmanager.mimir.svc.cluster.local:8080/alertmanager"
      
      # Filesystem-Backend aktivieren: Erlaubt HTTP API Schreibzugriffe (SetRuleGroup)
      ruler_storage:
        backend: filesystem
        filesystem:
          dir: /rules-storage

  ruler:
    enabled: true
    replicas: 1
    # Ein beschreibbares emptyDir-Volume an /rules-storage mounten (Lösung für readOnlyRootFilesystem)
    extraVolumes:
      - name: rules-storage
        emptyDir: {}
    extraVolumeMounts:
      - name: rules-storage
        mountPath: /rules-storage
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        memory: 512Mi

# Den alten ConfigMap Sync-Job vollständig deaktivieren
rulerRuleSync:
  enabled: false
```

### 1.2 Validierung von Schritt 1
Nachdem du die Änderungen gepusht hast und Argo CD die Mimir-Anwendung synchronisiert hat, prüfe folgendes:

1. **Ruler Pod Status prüfen:**
   ```bash
   kubectl get pods -n mimir -l "app.kubernetes.io/component=ruler"
   ```
   *Soll-Zustand:* Der Pod muss den Status `Running` und `1/1 Ready` haben.

2. **Ruler Logs prüfen (Sanity Check):**
   ```bash
   kubectl logs -n mimir -l "app.kubernetes.io/component=ruler" --tail=50
   ```
   *Soll-Zustand:* Suche in den Logs nach Zeilen wie:
   * `Checking directories read/write access`
   * `Directories read/write access successfully checked`
   * Wenn hier keine Fehlermeldung wie `read-only file system` erscheint, läuft das Volume korrekt!

---

## 🛠️ Schritt 2: Die neue App `alertprovider` (Crossplane) anlegen

Wir erstellen eine neue Helm-Wrapper-App (oder erweitern eine bestehende Crossplane-App), die den Crossplane Mimir-Provider installiert und die Rules CRs generiert.

### 2.1 Ordnerstruktur erstellen
Erstelle in deinem GitOps-Repository die folgende Struktur unter `apps/alertprovider/` (oder `apps/crossplane/`):

```text
apps/alertprovider/
├── Chart.yaml
├── values.yaml
├── files/
│   ├── mimir/
│   │   └── alerts-custom.yaml       # Deine benutzerdefinierten Mimir-Alerts
│   └── kubernetes/
│       └── grafana-prometheusRule.yaml # Deine Kubernetes-Infrastruktur-Alerts
└── templates/
    ├── provider-mimir.yaml          # Konfiguration des Crossplane Mimir Providers
    ├── mimir-ruler-rules.yaml       # Template zur Rule-Generierung
    └── mimir-alertmanager-config.yaml # Template für das Telegram-Routing
```

### 2.2 Helm Meta-Dateien schreiben

**`Chart.yaml`**:
```yaml
apiVersion: v2
name: alertprovider
description: Provisioniert Mimir Alerting Rules und Alertmanager Configs via Crossplane
type: application
version: 1.0.0
```

**`values.yaml`**:
```yaml
mimir:
  # Muss identisch sein mit dem X-Scope-OrgID Header, den Alloy beim Schreiben nach Mimir nutzt.
  tenantId: "1"
  endpoint: "http://mimir-gateway.mimir.svc.cluster.local"

rules:
  files:
    - "files/mimir/alerts-custom.yaml"
    - "files/kubernetes/grafana-prometheusRule.yaml"

alertmanager:
  enabled: true
  orgId: "1"
  receiverName: telegram
  telegram:
    chatId: 462723448
    botTokenSecretRef:
      name: grafana-secrets
      namespace: grafana
      key: GF_TELEGRAM_BOT_TOKEN
```

---

## 🛠️ Schritt 3: Crossplane Provider konfigurieren

Damit Crossplane mit der Mimir-API sprechen kann, müssen wir den Provider und seine Zugangsdaten (`ProviderConfig`) deklarieren.

**`templates/provider-mimir.yaml`**:
```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-mimir
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-mimir:v0.1.0 # Oder neuere Version
---
apiVersion: mimir.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: default
spec:
  # Die URL des Mimir-Gateways (über das interne Kubernetes-Netzwerk erreichbar)
  endpoint: {{ .Values.mimir.endpoint | quote }}
  # Wenn Mimir kein Auth nutzt, kann das leer bleiben oder als Dummy dienen
  headers:
    X-Scope-OrgID: {{ .Values.mimir.tenantId | quote }}
```

---

## 🛠️ Schritt 4: Rule-Dateien kopieren und Template erstellen

Kopiere deine bestehenden Rule-Dateien aus deinem alten Mimir-Verzeichnis (z. B. `apps/mimir/noctua/files/...`) in das Verzeichnis `apps/alertprovider/files/...`.

### 4.1 Das Rule-Template schreiben
Dieses Template generiert automatisch für jede YAML-Datei im `files/`-Ordner eine eigene Crossplane `Rules` Custom Resource. 

Da einige Kubernetes-Alerts im Prometheus-Operator-Format (`PrometheusRule`) vorliegen, Mimir aber rohes Prometheus-Format benötigt, implementieren wir eine **automatische On-the-fly-Konvertierung** im Template:

**`templates/mimir-ruler-rules.yaml`**:
```yaml
{{- /*
Dieses Template iteriert über alle registrierten Regeldateien,
liest deren Inhalt ein und konvertiert sie ggf. on-the-fly.
*/ -}}
{{- $ruleFiles := .Values.rules.files | default list }}

{{- range $filePath := $ruleFiles }}
{{- $fileContent := $.Files.Get $filePath }}
{{- if $fileContent }}
{{- /* Pfad bereinigen für den Kubernetes-Ressourcennamen (z.B. files/mimir/alerts.yaml -> mimir-rules-mimir-alerts) */ -}}
{{- $sanitized := $filePath | replace "/" "-" | replace "." "-" | replace "_" "-" | lower | trimPrefix "files-" | trimSuffix "-yaml" }}
---
apiVersion: ruler.mimir.crossplane.io/v1alpha1
kind: Rules
metadata:
  name: mimir-rules-{{ $sanitized }}
  annotations:
    argocd.argoproj.io/sync-wave: "15"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  forProvider:
    # WICHTIG: Der Mimir Rule-Namespace ist ein logischer Pfad/Ordner in Mimir.
    # Um Kollisionen zu verhindern und eine schöne Gruppierung in der Grafana-UI zu erreichen,
    # extrahieren wir den Namen des Verzeichnisses (z. B. "mimir", "kubernetes") aus dem Dateipfad!
    {{- $mimirNamespace := dir $filePath | trimPrefix "files/" }}
    namespace: {{ $mimirNamespace | quote }}
    content: |
      {{- /* Parser: Prüfen ob es sich um eine Kubernetes PrometheusRule CRD handelt */ -}}
      {{- $yaml := $fileContent | fromYaml }}
      {{- if and $yaml.spec $yaml.spec.groups }}
      # Automatisch konvertiert aus PrometheusRule CRD
      groups:
      {{- toYaml $yaml.spec.groups | nindent 6 }}
      {{- else }}
      # Direkt importiertes Prometheus-Rohformat
      {{- $fileContent | nindent 6 }}
      {{- end }}
  providerConfigRef:
    name: default
{{- end }}
{{- end }}
```

---

## 🛠️ Schritt 5: Notification Routing (Telegram) definieren

Erstelle die Routing-Konfiguration für den Mimir Alertmanager. Hier definierst du, wohin deine Alarme gesendet werden (z. B. Telegram).

**`templates/mimir-alertmanager-config.yaml`**:
```yaml
{{- if .Values.alertmanager.enabled }}
apiVersion: alertmanager.mimir.crossplane.io/v1alpha1
kind: Config
metadata:
  name: mimir-alertmanager-config
  annotations:
    # Der Tenant, dem diese Konfiguration gehört.
    crossplane.io/external-name: {{ .Values.alertmanager.orgId | quote }}
    argocd.argoproj.io/sync-wave: "15"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  forProvider:
    orgId: {{ .Values.alertmanager.orgId | quote }}
    route:
      - receiver: {{ .Values.alertmanager.receiverName | quote }}
        groupBy:
          - alertname
        groupWait: 10s
        groupInterval: 10s
        # Wiederholungsintervall für aktive Alerts (z.B. alle 4 Stunden)
        repeatInterval: 4h
    receiver:
      - name: {{ .Values.alertmanager.receiverName | quote }}
        telegramConfigs:
          - chatId: {{ .Values.alertmanager.telegram.chatId }}
            botTokenSecretRef:
              name: {{ .Values.alertmanager.telegram.botTokenSecretRef.name | quote }}
              namespace: {{ .Values.alertmanager.telegram.botTokenSecretRef.namespace | quote }}
              key: {{ .Values.alertmanager.telegram.botTokenSecretRef.key | quote }}
  providerConfigRef:
    name: default
{{- end }}
```

Wenn stattdessen der **Grafana Alertmanager** genutzt werden soll, wird diese Datei nicht benötigt. Dann müssen im Grafana-Chart stattdessen `GrafanaContactPoint` und `GrafanaNotificationPolicy` gerendert werden, und `mimir-distributed.mimir.structuredConfig.ruler.alertmanager_url` muss auf die Grafana-Alertmanager-API zeigen.

---

## 🚀 Schritt 6: Deployment und Validierung

Sobald du die neue App `alertprovider` in Argo CD registriert und synchronisiert hast, führen wir die Validierung durch.

### 6.0 Helm-Render-Test vor dem Merge

Bevor die Änderung gemerged wird, muss lokal geprüft werden, ob Helm wirklich die erwarteten Ressourcen rendert. Das ist der schnellste Weg, um Template-Fehler, falsche Einrückungen oder fehlende CRDs früh zu finden.

```bash
# Mimir-Konfiguration prüfen
helm template apps/mimir/noctua \
  -f apps/mimir/base/values.yaml \
  -f apps/mimir/noctua/values.yaml \
  | grep -nE "ruler_storage|rules-storage|alertmanager_url|backend: filesystem"

# Alertprovider / Crossplane-Ressourcen prüfen
helm template apps/alertprovider \
  | grep -nE "kind: Provider|kind: ProviderConfig|kind: Rules|kind: Config|X-Scope-OrgID|namespace:"
```

*Soll-Zustand:*
* `ruler_storage.backend` ist `filesystem`.
* `/rules-storage` ist als beschreibbares Volume im Ruler vorhanden.
* `X-Scope-OrgID`, Rule-`namespace` und Alertmanager-`orgId` verwenden denselben Tenant.
* Es werden `Provider`, `ProviderConfig`, `Rules` und optional `Config` gerendert.

### 6.1 Status der Crossplane Ressourcen prüfen
Lasse dir alle Crossplane-Rules-Objekte im Cluster anzeigen:
```bash
kubectl get rules.ruler.mimir.crossplane.io
```

*Soll-Zustand:* Alle Einträge müssen in den Spalten `SYNCED` und `READY` ein `True` aufweisen:
```text
NAME                                         SYNCED   READY   EXTERNAL-NAME   AGE
mimir-rules-mimir-alerts-custom              True     True    1/1             5m
mimir-rules-kubernetes-grafana-prometheus    True     True    1/1             5m
```

Falls ein Status auf `False` steht, beschreibe die Ressource, um den genauen Fehler der Mimir-API zu sehen:
```bash
kubectl describe rules.ruler.mimir.crossplane.io mimir-rules-mimir-alerts-custom
```
*Tipp bei Fehlern:* Achte im `status`-Block auf Fehlermeldungen der Mimir-Ruler-API (z.B. Syntaxfehler in PromQL-Queries).

---

### 6.2 Live-Abfrage der Mimir Ruler API (Der ultimative Beweis)

Da der Ruler die Regeln nun direkt in sein schreibbares Verzeichnis `/rules-storage` legt, können wir über die HTTP-API abfragen, ob Mimir die Regeln tatsächlich geladen hat und evaluiert.

1. **Port-Forward zum Mimir Ruler starten:**
   ```bash
   kubectl port-forward svc/mimir-ruler 8080:8080 -n mimir
   ```
   *(Lass dieses Terminalfenster offen)*

2. **In einem zweiten Terminal die API abfragen:**
   ```bash
   curl -s -H "X-Scope-OrgID: 1" http://localhost:8080/prometheus/api/v1/rules | grep -o '"name":"[^"]*"'
   ```

*Soll-Zustand:* Es wird eine Liste aller geladenen Rule-Groups ausgegeben. Du solltest deine konfigurierten Alerts (z.B. aus `alerts-custom.yaml` und `grafana-prometheusRule.yaml`) in dieser Liste wiederfinden.

---

### 6.3 Alertmanager Status validieren
Prüfe, ob Crossplane die Alertmanager-Konfiguration erfolgreich an Mimir übergeben hat:
```bash
kubectl get configs.alertmanager.mimir.crossplane.io mimir-alertmanager-config
```

*Soll-Zustand:*
```text
NAME                        SYNCED   READY   EXTERNAL-NAME   AGE
mimir-alertmanager-config   True     True    1               5m
```
Der Mimir Alertmanager leitet nun eintreffende Alerts gemäß der in Schritt 5 deklarierten Telegram-Konfiguration weiter.

---

## 🧩 Optional: Wenn Grafana Operator das Routing übernehmen soll

Wenn das Zielbild wie in der `dev-observability`-Referenz ist, kann der Mimir Ruler weiterhin die Plattform-Alerts auswerten, aber die Benachrichtigung an den **Grafana Alertmanager** übergeben. Dann gilt:

1. `mimir-alertmanager-config.yaml` aus Schritt 5 deaktivieren oder löschen.
2. In Mimir `structuredConfig.ruler.alertmanager_url` auf Grafana setzen:
  ```yaml
  alertmanager_url: http://grafana.grafana.svc.cluster.local/api/alertmanager/grafana
  ```
3. Falls Grafana Auth benötigt, müssen Basic-Auth- oder Header-Einstellungen sauber als Secret eingebunden werden.
4. Contact Points deklarativ im Grafana-Chart anlegen, z. B. als `GrafanaContactPoint`.
5. Routing deklarativ im Grafana-Chart anlegen, z. B. als `GrafanaNotificationPolicy`.

Validierung:

```bash
kubectl get grafanacontactpoints.grafana.integreatly.org -A
kubectl get grafananotificationpolicies.grafana.integreatly.org -A
```

*Soll-Zustand:* Contact Points und Notification Policies sind vorhanden und `No matching route` oder Blackhole-Fallbacks treten nur für bewusst ignorierte Alerts auf.
