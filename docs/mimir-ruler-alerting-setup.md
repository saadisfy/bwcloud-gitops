# Mimir Ruler & Alerting Setup

Dieses Dokument beschreibt die vollständige Konfiguration des Mimir-Rulers,
wie Alert-Rules verwaltet werden, wie sie in Mimir geladen werden und welche
Design-Entscheidungen dabei getroffen wurden.

---

## Überblick: Wie kommen Alerts in Mimir?

```
Git (files/**/*.yaml)
       │
       ▼
Helm-Template (ruler-rules-configmap.yaml)
       │  Aggregiert alle alerts*.yaml → ein kombiniertes ConfigMap
       ▼
ConfigMap: mimir-rules-bundle (Namespace: mimir)
       │
       ▼  subPath-Mount (readOnly)
Ruler-Pod: /rules-storage/1/rules.yaml
       │
       ▼  ruler_storage.backend=local liest direkt beim Start
Mimir Ruler evaluiert Alerts → feuert an Alertmanager
```

Kein Job. Kein API-Call. Kein Chicken-and-Egg. Rules sind bei jedem Pod-Start sofort vorhanden.

---

## 1. Alert-Rule-Dateien

### Ablageort

```
apps/mimir/prod/files/
├── kubernetes/
│   ├── alerts.yaml          # Kubernetes-App-Alerts (KubePodCrashLooping, etc.)
│   └── alerts-rules.yaml    # Kubernetes Recording Rules (apiserver availability, etc.)
└── mimir/
    ├── alerts.yaml          # Mimir-interne Alerts (MimirIngesterUnhealthy, etc.)
    ├── alerts-rules.yaml    # Mimir Recording Rules (cortex_request latency quantiles, etc.)
    └── alerts-custom.yaml   # Custom Alerts (MimirIngesterFlushQueueHigh, etc.)
```

### Format

Jede Datei ist Standard-Prometheus-YAML mit `groups:` auf der obersten Ebene:

```yaml
# Beispiel: files/mimir/alerts-custom.yaml
groups:
  - name: mimir_custom_alerts
    rules:
      - alert: MimirIngesterFlushQueueHigh
        annotations:
          message: "Mimir Ingester {{ $labels.pod }} has {{ $value }} series waiting..."
        expr: sum by (namespace, pod) (cortex_ingester_flush_queues_length) > 5000
        for: 5m
        labels:
          severity: warning
```

### Glob-Pattern

Das Helm-Template erkennt Dateien über:

```
files/**/alerts*.yaml
files/**/alerts*.yml
```

Neue Dateien mit diesem Namensmuster werden **automatisch** beim nächsten Helm-Render aufgenommen.

---

## 2. Helm-Template: ConfigMap-Aggregation

**Datei:** `apps/mimir/prod/templates/ruler-rules-configmap.yaml`

```yaml
{{- $cfg := .Values.rulerRuleSync | default dict }}
{{- if ($cfg.enabled | default false) }}
{{- $ruleGlobs := list "files/**/alerts*.yaml" "files/**/alerts*.yml" }}
{{- $ruleFiles := dict }}
{{- range $glob := $ruleGlobs }}
{{- range $path, $_ := $.Files.Glob $glob }}
{{- $_ = set $ruleFiles $path true }}
{{- end }}
{{- end }}

{{- if gt (len $ruleFiles) 0 }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: mimir-rules-bundle
  namespace: {{ .Release.Namespace }}
data:
  rules.yaml: |-
    groups:
{{- range $path, $_ := $ruleFiles }}
{{- $fileContent := $.Files.Get $path | fromYaml }}
{{- if $fileContent.groups }}
{{ toYaml $fileContent.groups | nindent 6 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
```

**Was passiert hier:**
- Alle `alerts*.yaml` Dateien unter `files/` werden per Glob eingelesen
- Ihre `groups:`-Blöcke werden zu einer einzigen `rules.yaml` zusammengemergt
- Diese landet im ConfigMap `mimir-rules-bundle` im Namespace `mimir`
- Das Template wird nur gerendert wenn `rulerRuleSync.enabled: true`

**Aktivierung** (`apps/mimir/prod/values.yaml`):
```yaml
rulerRuleSync:
  enabled: true
  argocdHook: false   # kein ArgoCD-Job mehr
```

---

## 3. Ruler-Storage: `local` Backend

### Warum `local` und nicht `filesystem`?

| Backend | Speicherformat | Lesbar per `cp`? | Für GitOps geeignet? |
|---|---|---|---|
| `filesystem` | Internes Encoding (object-storage-ähnlich) | ❌ Nein | ❌ Nein |
| `local` | Standard Prometheus-YAML, read-only | ✅ Ja | ✅ Ja |

Das `local`-Backend ist speziell für statisch verwaltete Rules gedacht — genau unser GitOps-Use-Case.

### Konfiguration in `prod/values.yaml`

```yaml
mimir-distributed:
  mimir:
    structuredConfig:
      ruler:
        # Temp-Verzeichnis für Rule-Evaluation (muss beschreibbar sein).
        # /tmp ist NICHT nutzbar: readOnlyRootFilesystem=true im Ruler-Container.
        # EmptyDir-Volume (storage) ist unter /data gemountet → beschreibbar.
        rule_path: /data/ruler-rules

        alertmanager_url: "http://mimir-alertmanager-headless.mimir.svc.cluster.local:8080"

      ruler_storage:
        backend: local
        local:
          # Mimir liest aus: /rules-storage/<tenantId>/<namespace>.yaml
          # → /rules-storage/1/rules.yaml  (Tenant=1, Namespace=rules)
          directory: /rules-storage
```

### Warum `rule_path: /data/ruler-rules` statt `/tmp`?

Der Mimir-Ruler-Container läuft mit `readOnlyRootFilesystem: true` (gesetzt durch das upstream `mimir-distributed` Helm-Chart). Das bedeutet:

- `/tmp` → **read-only** → Ruler crasht beim Start mit:
  `ruler: failed to access directory /tmp/ruler-rules: open /tmp/.check: read-only file system`
- `/data` → **beschreibbares EmptyDir-Volume** → funktioniert

Die `base/values.yaml` setzt `rule_path: /tmp/ruler-rules` (Standard für dev). Die `prod/values.yaml` **überschreibt** diesen Wert auf `/data/ruler-rules`.

---

## 4. ConfigMap-Mount auf den Ruler-Pod

### Das Dateisystem-Mapping

Mimir `local`-Backend erwartet Rules in dieser Struktur:

```
<directory>/
└── <tenantId>/
    └── <namespace>.yaml
```

Mit `directory: /rules-storage` und Tenant-ID `1`:

```
/rules-storage/
└── 1/
    └── rules.yaml    ← hier muss die Datei liegen
```

### Mount-Konfiguration (`prod/values.yaml`)

```yaml
mimir-distributed:
  ruler:
    extraVolumes:
      - name: ruler-rules-storage
        configMap:
          name: mimir-rules-bundle    # das ConfigMap aus Schritt 2

    extraVolumeMounts:
      - name: ruler-rules-storage
        mountPath: /rules-storage/1/rules.yaml   # exakter Zielpfad
        subPath: rules.yaml                       # Key im ConfigMap
        readOnly: true
```

**Warum `subPath`?**
Ohne `subPath` würde Kubernetes das ganze Verzeichnis `/rules-storage/1/` durch das ConfigMap ersetzen. Mit `subPath` wird nur die einzelne Datei `rules.yaml` gemountet, ohne andere Dateien im Verzeichnis zu überschreiben.

---

## 5. Ruler-Pod: Volumes im Überblick

```
Ruler-Pod (mimir-ruler-<hash>)
│
├── InitContainers:
│   └── setup-storage         (busybox)
│       └── mkdir -p /data/blocks
│           → bereitet EmptyDir vor (blocks_storage braucht das Verzeichnis)
│
├── Volumes:
│   ├── storage    (EmptyDir)        → /data          (beschreibbar: rule_path, blocks)
│   ├── config     (ConfigMap)       → /etc/mimir      (mimir.yaml Config)
│   ├── runtime-config (ConfigMap)   → /var/mimir      (runtime overrides)
│   └── ruler-rules-storage (ConfigMap: mimir-rules-bundle)
│       └── subPath: rules.yaml      → /rules-storage/1/rules.yaml  (readOnly)
│
└── Container: ruler (grafana/mimir:3.0.1)
    ├── /data/ruler-rules    ← rule_path (temp Evaluation, beschreibbar via EmptyDir)
    ├── /rules-storage/1/rules.yaml ← Prometheus YAML, direkt gemountet
    └── readOnlyRootFilesystem: true
```

---

## 6. Automatische Rule-Aktualisierung (GitOps-Loop)

### Wie werden neue/geänderte Alerts deployed?

```
1. Entwickler ändert eine Datei in apps/mimir/prod/files/**
2. git commit && git push → main
3. Argo CD erkennt Änderung → rendert Helm neu
4. mimir-rules-bundle ConfigMap wird aktualisiert
5. Stakater Reloader erkennt ConfigMap-Änderung (reloader.stakater.com/auto: "true")
6. Reloader annotiert den Ruler-Deployment → Rolling Restart
7. Neuer Ruler-Pod startet → liest /rules-storage/1/rules.yaml direkt beim Boot
8. Alerts sind sofort aktiv
```

### Stakater Reloader — wo konfiguriert?

In `apps/mimir/base/values.yaml`:

```yaml
mimir-distributed:
  global:
    podAnnotations:
      reloader.stakater.com/auto: "true"
```

Diese Annotation gilt für **alle** Mimir-Pods. Reloader überwacht alle ConfigMaps/Secrets die von Pods gemountet werden und triggert Restarts bei Änderungen.

---

## 7. Alertmanager-Konfiguration

### Verbindung Ruler → Alertmanager

Der Ruler sendet gefeuerte Alerts an den Alertmanager via:

```yaml
ruler:
  alertmanager_url: "http://mimir-alertmanager-headless.mimir.svc.cluster.local:8080"
```

**Headless Service** (`mimir-alertmanager-headless`) wird verwendet damit der Ruler alle Alertmanager-Instanzen direkt ansprechen kann (bei >1 Replica), ohne durch einen Load-Balancer zu gehen — wichtig für Alertmanager-Clustering.

### Alertmanager-Storage (`base/values.yaml`)

```yaml
mimir-distributed:
  mimir:
    structuredConfig:
      alertmanager:
        data_dir: /tmp/alertmanager-data    # Alertmanager darf /tmp nutzen (kein readOnly rootfs)
      alertmanager_storage:
        backend: local
        local:
          path: /data    # PersistentVolume für Alertmanager-State
```

Der Alertmanager hat **kein** `readOnlyRootFilesystem` Problem — das betrifft nur den Ruler-Container.

### Alertmanager Fallback-Config (`base/values.yaml`)

```yaml
alertmanager:
  fallbackConfig: |
    global:
      resolve_timeout: 5m
    route:
      receiver: default-receiver
    receivers:
      - name: default-receiver
```

Wenn kein Tenant eine eigene Alertmanager-Config hat, wird diese Fallback-Config verwendet. Alert-Routing (Slack, PagerDuty, etc.) muss separat pro Tenant konfiguriert werden.

---

## 8. Was wurde gegenüber dem alten Ansatz (Job) geändert

### Alter Ansatz (kaputt)

```
ArgoCD Sync
  → rendert Job: mimir-rules-sync-<checksum>
  → Job startet mimirtool gegen Gateway API
  → PROBLEM 1: Job-Name fix → "already exists" bei jedem Sync
  → PROBLEM 2: mimirtool braucht laufenden Ruler (Chicken-and-Egg)
  → PROBLEM 3: filesystem-Backend ignoriert direktes cp
```

### Neuer Ansatz (funktioniert)

```
Git Push
  → Argo rendert ConfigMap mimir-rules-bundle neu
  → Reloader erkennt ConfigMap-Änderung
  → Ruler-Pod Restart
  → local-Backend liest rules.yaml direkt beim Start
  → fertig
```

### Dateien die geändert wurden

| Datei | Änderung |
|---|---|
| `apps/mimir/prod/templates/ruler-rules-sync.yaml` | Job-Template entfernt, nur Kommentar |
| `apps/mimir/prod/values.yaml` | `ruler_storage.backend: local`, `extraVolumeMounts` mit subPath, `rule_path: /data/ruler-rules` |

---

## 9. Neue Alert-Rules hinzufügen

1. Neue YAML-Datei anlegen: `apps/mimir/prod/files/<kategorie>/alerts-<name>.yaml`
2. Standard Prometheus-Format verwenden (muss mit `groups:` beginnen)
3. Committen und pushen
4. Argo CD + Reloader übernehmen den Rest automatisch

**Beispiel:**
```yaml
# apps/mimir/prod/files/mimir/alerts-my-custom.yaml
groups:
  - name: my_custom_alerts
    rules:
      - alert: MyAlert
        expr: up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} down"
```
