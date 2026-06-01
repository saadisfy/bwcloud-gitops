# Step-by-Step Anleitung: Migration von ConfigMap-basierten Mimir-Rules auf Crossplane Provisionierung

Diese Anleitung richtet sich an Junior-Engineers und Einsteiger. Sie beschreibt Schritt für Schritt, wie man eine bestehende, ConfigMap-basierte Rule-Synchronisation in Grafana Mimir auf eine moderne, API-gestützte Bereitstellung mittels **Crossplane** umstellt.

---

## 📋 Ausgangslage
* **Crossplane** ist bereits im Kubernetes-Cluster installiert.
* **Mimir** ist installiert und speichert seine TSDB-Blöcke bereits erfolgreich in S3/MinIO.
* **Der Mimir Ruler** läuft aktuell mit dem Backend `local` und lädt seine Regeln über ein ConfigMap-Volume-Mount unter `/rules-storage`.
* **Ziel:** Die Regeln sowie die Benachrichtigungskanäle (Alertmanager Config) sollen stattdessen über Crossplane provisioniert werden.

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
# Derzeit keine Werte benötigt, da alles über statische Files oder Templates läuft.
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
  endpoint: http://mimir-gateway.mimir.svc.cluster.local
  # Wenn Mimir kein Auth nutzt, kann das leer bleiben oder als Dummy dienen
  headers:
    X-Scope-OrgID: "1"
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
{{- $ruleFiles := list
    "files/mimir/alerts-custom.yaml"
    "files/kubernetes/grafana-prometheusRule.yaml"
}}

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
    # Um Kollisionen zwischen verschiedenen Deployments/Teams zu verhindern,
    # nutzen wir hier dynamisch den Helm Release Namen anstelle eines statischen Wertes!
    namespace: {{ .Release.Name | quote }}
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
apiVersion: alertmanager.mimir.crossplane.io/v1alpha1
kind: Config
metadata:
  name: mimir-alertmanager-config
  annotations:
    # Der Tenant, dem diese Konfiguration gehört ("1")
    crossplane.io/external-name: "1"
    argocd.argoproj.io/sync-wave: "15"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  forProvider:
    orgId: "1"
    route:
      - receiver: telegram
        groupBy:
          - alertname
        groupWait: 10s
        groupInterval: 10s
        # Wiederholungsintervall für aktive Alerts (z.B. alle 4 Stunden)
        repeatInterval: 4h
    receiver:
      - name: telegram
        telegramConfigs:
          - chatId: 462723448 # Deine Telegram Gruppen/Kanal-ID
            botTokenSecretRef:
              name: grafana-secrets
              namespace: grafana
              key: GF_TELEGRAM_BOT_TOKEN
  providerConfigRef:
    name: default
```

---

## 🚀 Schritt 6: Deployment und Validierung

Sobald du die neue App `alertprovider` in Argo CD registriert und synchronisiert hast, führen wir die Validierung durch.

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
