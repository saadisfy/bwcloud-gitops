# 🚀 Grafana How-To: Multi-Tenancy & RBAC in Grafana Open Source (OSS)

> [!IMPORTANT]
> **Das Mandat / Die Problemstellung (Requirements & Constraints):**
> 
> * **Ausgangssituation:** Ein einziges Kubernetes-Cluster betreibt den Grafana-LGTM-Stack (Loki, Grafana, Tempo, Mimir) im Single-Tenant-Modus. Alle Telemetriedaten werden an den Tenant `anonymous` gesendet. Alle User loggen sich in dieselbe Standard-Grafana-Org ein und sehen sämtliche Daten (Sicherheitsrisiko).
> * **Anforderung:** Datentrennung (Multi-Tenancy) und Rollenberechtigungen (RBAC) müssen für verschiedene Mandanten (z.B. `tenant-a`, `tenant-b`) so implementiert werden, dass jeder Kunde nur seine eigenen Anwendungsdaten sieht, aber auch globale Infrastrukturmetriken (wie Kube-State-Metrics oder Node-Exporter) einsehen kann.
> * **Vorgegebene Constraints (Einschränkungen):**
>   1. **Reine Open-Source-Mittel:** Keine Lizenzierung von Grafana Enterprise oder Wechsel zu Grafana Cloud.
>   2. **Single-Grafana-Instanz:** Keine Multiplikation von Grafana-Instanzen pro Kunde (Ressourceneffizienz).
>   3. **Automatisierung (GitOps):** Onboarding neuer Kunden darf keine manuellen Eingriffe erfordern, sondern muss rein deklarativ in GitOps erfolgen (Argo CD gesteuert).
>   4. **Grafana OSS-Beschränkung:** Da Datei-basierte Provisionierung in Grafana OSS bei nicht-existenten Organisationen fehlschlägt, müssen Organisationen und Datenquellen dynamisch beim Start über die HTTP-API erstellt und zugewiesen werden.
>   5. **Infrastruktur-Zusatz:** Die Auto-Instrumentation (OTel Operator) muss die Tenant-ID automatisch basierend auf dem Namespace des Pods an das Alloy-Gateway übertragen.
>   6. **Storage & Ingestion:** Mimir und Loki müssen die Daten physisch trennen (Unterordner im S3/GCS-Bucket) und Ingester-Ressourcen isolieren (Shuffle Sharding) zur Absicherung gegen "Noisy Neighbors".
> 
> **Dieses Dokument beschreibt Schritt-für-Schritt die technische Lösung, die diese komplexen Anforderungen erfüllt.**

---

## 📖 Inhaltsverzeichnis
1. [Ausgangslage vs. Zielbild (Die Migration)](#1-ausgangslage-vs-zielbild-die-migration)
2. [Die 3 Säulen der Grafana OSS Multi-Tenancy](#2-die-3-säulen-der-grafana-oss-multi-tenancy)
3. [Grafana Multi-Org & Datenquellen-Setup](#3-grafana-multi-org--datenquellen-setup)
4. [SSO-Anbindung & Org-Mapping (Entra ID & GitHub)](#4-sso-anbindung--org-mapping-entra-id--github)
5. [Telemetry Ingestion: OpenTelemetry & Grafana Alloy](#5-telemetry-ingestion-opentelemetry--grafana-alloy)
6. [Mimir & Loki: Ingester- & Storage-Architektur](#6-mimir--loki-ingester--storage-architektur)
7. [Vorteile für die Query-Performance](#7-vorteile-für-die-query-performance)
8. [Onboarding-Leitfaden für neue Kunden](#8-onboarding-leitfaden-für-neue-kunden)
9. [Sicherheitsanalyse & Einschränkungen](#9-sicherheitsanalyse--einschränkungen)

---

## 1. Ausgangslage vs. Zielbild (Die Migration)

### 🔴 Ausgangslage (Single-Tenant Baseline)
Zuvor war die gesamte Observability-Infrastruktur im **Single-Tenant-Modus** konfiguriert:
* **Ingestion:** Alle Anwendungen, Kubernetes-Systemkomponenten (Kube-State-Metrics, Node-Exporter) und Log-Kollektoren sendeten ihre Daten an Mimir und Loki mit dem statischen Header `X-Scope-OrgID: "anonymous"` (oder Tenant 1).
* **Visualisierung:** Grafana lief in einer einzigen Standard-Organisation (`Main Org.`). Alle Benutzer wurden nach dem SSO-Login in diese Organisation geleitet.
* **Das Problem:** Alle Entwickler und Kunden konnten sämtliche Metriken, Logs und Traces des gesamten Clusters einsehen. Es gab keine logische oder physische Trennung.

### 🟢 Zielbild (Multi-Tenant Target State)
Das Ziel ist eine vollständige Isolation der Mandantendaten im laufenden Betrieb unter Verwendung von Open-Source-Constructs:
1. **Logische Isolation (Grafana):** Jedes Kundenteam erhält eine eigene Grafana-Organisation (z. B. Org 2 = `Tenant-A`, Org 3 = `Tenant-B`). Diese Organisationen sind komplett voneinander getrennt (Dashboards, Alert-Regeln, Benutzer-Zuweisung).
2. **Daten-Isolation (Mimir/Loki/Tempo):** Die Datenquellen innerhalb einer Kunden-Organisation greifen über einen zusammengesetzten Header (`tenant-a,infrastructure`) auf die Daten zu. Der Kunde sieht nur seine eigenen Anwendungsdaten (aus dem Namespace `tenant-a`) sowie geteilte Infrastrukturdaten (CPU-Auslastung der Nodes, K8s-Objekte).
3. **Physische Storage-Isolation:** Die Rohdaten im Cloud Storage (S3/GCS) werden physisch in getrennten Unterordnern (Präfixen) pro Tenant abgelegt.

---

## 2. Die 3 Säulen der Grafana OSS Multi-Tenancy

Grafana OSS erlaubt die Provisionierung von Datenquellen und Dashboards über YAML-Dateien standardmäßig nur für die Standard-Organisation (ID `1`). Wenn man versucht, Datenquellen für nicht-existente Organisationen (ID $\ge 2$) beim Start zu provisionieren, bricht der Grafana-Startprozess mit einem Fehler ab.

Um dieses Problem zu lösen, implementieren wir eine **dreistufige API-Bootstrapping-Architektur**:

```
[ Grafana Pod Startup ]
         │
         ├──► 1. Startet Hauptprozess (lädt nur default Org 1)
         │
         └──► 2. postStart Hook (führt bootstrap.sh im Hintergrund aus)
                     │
                     ├──► Erstellt Orgs (Tenant-A, Tenant-B) via HTTP API
                     ├──► Löscht/Erstellt Datenquellen pro Org (z.B. Org 2 -> tenant-a)
                     └──► Kopiert Dashboards aus /tmp/dashboards in alle Kunden-Orgs
```

1. **Datei-basiertes Provisioning (nur für Org 1):** Die Standard-Datenquellen werden wie gewohnt deklariert, um den Startabsturz zu verhindern.
2. **K8s Sidecar:** Ein Sidecar-Container scannt den Namespace nach Dashboard-ConfigMaps und lädt diese in ein gemeinsames Verzeichnis `/tmp/dashboards` herunter.
3. **Bootstrap-API-Skript:** Ein Kubernetes `postStart`-Lifecycle-Hook führt nach dem Anlauf des Containers das Skript `/opt/bootstrap/bootstrap.sh` im Hintergrund aus. Dieses Skript erstellt die Organisationen live via API, richtet die kunden-spezifischen Datenquellen ein und kopiert die heruntergeladenen Dashboards in alle Organisationen.

---

## 3. Grafana Multi-Org & Datenquellen-Setup

### Das Bootstrap-Skript (ConfigMap)
Unter `apps/grafana/noctua/templates/grafana-bootstrap-script.yaml` liegt das Bash-Skript, welches bei jedem Pod-Start ausgeführt wird:

```sh
#!/bin/sh
# Warten auf Grafana API
until $(curl -s -f -o /dev/null http://localhost:3000/api/health); do
  echo "Warte auf Grafana API..."
  sleep 2
done

# Admin-Passwort aktualisieren (idempotent)
curl -X PUT -H "Content-Type: application/json" -d '{"oldPassword":"admin","newPassword":"'"$GF_SECURITY_ADMIN_PASSWORD"'"}' http://admin:admin@localhost:3000/api/user/password || true

# Helper-Funktion zum Erstellen einer Org
create_org() {
  NAME=$1
  curl -s -u "admin:$GF_SECURITY_ADMIN_PASSWORD" -X POST -H "Content-Type: application/json" -d '{"name":"'"$NAME"'"}' http://localhost:3000/api/orgs
}

# Helper-Funktion zur Provisionierung von Datenquellen
provision_datasources() {
  ORG_ID=$1
  TENANT_NAME=$2
  
  # Mimir Datenquelle in Org anlegen (injected tenant-specific headers)
  curl -s -u "admin:$GF_SECURITY_ADMIN_PASSWORD" -H "X-Grafana-Org-Id: $ORG_ID" -X POST -H "Content-Type: application/json" -d '{
    "name": "Mimir",
    "type": "prometheus",
    "access": "proxy",
    "url": "http://mimir-query-frontend.mimir.svc.cluster.local:8080/prometheus",
    "isDefault": true,
    "jsonData": {
      "httpHeaderName1": "X-Scope-OrgID",
      "manageAlerts": true,
      "alertmanagerUid": "mimir-alertmanager"
    },
    "secureJsonData": {
      "httpHeaderValue1": "'"$TENANT_NAME"',infrastructure"
    }
  }' http://localhost:3000/api/datasources
}
```

### Aktivierung in den Helm Values
Um das Skript einzubinden, werden die Mounts und Hooks konfiguriert:

**In `apps/grafana/base/values.yaml`:**
```yaml
grafana:
  lifecycleHooks:
    postStart:
      exec:
        command:
          - /bin/sh
          - -c
          - '/bin/sh /opt/bootstrap/bootstrap.sh &'

  sidecar:
    dashboards:
      enabled: true
      label: app.kubernetes.io/component
      labelValue: dashboard
```

**In `apps/grafana/noctua/values.yaml`:**
```yaml
grafana:
  extraConfigmapMounts:
    - name: grafana-bootstrap-script
      mountPath: /opt/bootstrap
      configMap: grafana-bootstrap-script
      readOnly: true
```

---

## 4. SSO-Anbindung & Org-Mapping (Entra ID & GitHub)

Beim Login über OAuth mappt Grafana Benutzer anhand ihrer ID-Provider-Gruppen automatisch auf die erstellten Grafana-Organisationen.

### A. Microsoft Entra ID (Azure AD)
In der Generic OAuth-Sektion der `grafana.ini` wird das Mapping über Gruppen-IDs gesteuert:
```yaml
grafana:
  grafana.ini:
    auth.generic_oauth:
      enabled: true
      name: Microsoft Entra ID
      allow_sign_up: true
      scopes: openid email profile offline_access
      role_attribute_path: "contains(roles, 'GrafanaAdmin') && 'Admin' || 'Viewer'"
      role_attribute_strict: true
      org_attribute_path: roles || groups
      # Format: <Entra_Group_Object_ID>:<GrafanaOrgID>:<GrafanaRolle>
      org_mapping: "3f8b0561-1234-5678-abcd-ef0123456789:2:Viewer, 4a9c1234-abcd-ef01-2345-6789abcdef01:3:Viewer"
```

### B. GitHub OAuth
Bei GitHub erfolgt das Mapping anhand der GitHub-Organisation und des Teams:
```yaml
grafana:
  grafana.ini:
    auth.github:
      enabled: true
      name: GitHub
      allow_sign_up: true
      scopes: user:email,read:org
      role_attribute_path: "login == 'saadisfy' && 'Admin' || 'Viewer'"
      role_attribute_strict: true
      # Format: <GitHubOrg>/<GitHubTeam>:<GrafanaOrgID>:<GrafanaRolle>
      org_mapping: "saadisfy-org/team-a:2:Viewer, saadisfy-org/team-b:3:Viewer"
```

---

## 5. Telemetry Ingestion: OpenTelemetry & Grafana Alloy

Damit Mimir und Loki wissen, welche Metrik zu welchem Mandanten gehört, muss jedes Datensignal bereits beim Verlassen des Pods mit der entsprechenden Tenant-ID markiert sein.

### A. Dynamische Injektion via Downward API (OTel Operator)
Der OpenTelemetry Operator injiziert den OTel-Java-Agenten in unsere Anwendungs-Pods. Über das `Instrumentation`-Manifest des Operators injecten wir die Tenant-ID dynamisch auf Basis des Kubernetes-Namespaces.

Unter `apps/otel-operator/noctua/templates/instrumentation-java.yaml`:
```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: java-instrumentation
  namespace: otel-operator
spec:
  env:
    # 1. Liest den aktuellen K8s-Namespace des Pods aus
    - name: K8S_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
          
    # 2. Setzt den OTLP-Exporter Header auf den Wert von K8S_NAMESPACE
    - name: OTEL_EXPORTER_OTLP_HEADERS
      value: "X-Scope-OrgID=$(K8S_NAMESPACE)"
```
* **Kubelet Env-Expansion:** Beim Start des Anwendungscontainers wertet Kubelet `K8S_NAMESPACE` aus (z. B. `tenant-a`). Da die Variable `OTEL_EXPORTER_OTLP_HEADERS` danach definiert ist, wird sie zu `X-Scope-OrgID=tenant-a` expandiert. Der Java-Agent sendet daraufhin alle Daten mit diesem Header.

### B. Alloy Pipeline & Metadata-Forwarding
Grafana Alloy empfängt die OTLP-Signale über den OTLP-Receiver. 
* Um sicherzustellen, dass die HTTP-Header nicht verloren gehen, wird der OTLP-Receiver mit `include_metadata = true` konfiguriert.
* Alloy leitet die Daten an den Mimir-Distributor weiter.

---

## 6. Mimir & Loki: Ingester- & Storage-Architektur

### A. Distributor, Ingester, Ruler & Alertmanager
Prometheus Mimir ist intern modular aufgebaut. Jede Komponente verhält sich mandantenfähig:

```
                  ┌──────────────────────────────────────────────┐
                  │   OpenTelemetry Auto-Instrumentation (App)   │
                  └──────────────────────┬───────────────────────┘
                                         │ OTLP mit Header:
                                         │ "X-Scope-OrgID: tenant-a"
                                         ▼
                  ┌──────────────────────────────────────────────┐
                  │            Grafana Alloy Gateway             │
                  └──────────────────────┬───────────────────────┘
                                         │ OTLP / Remote Write
                                         ▼
                  ┌──────────────────────────────────────────────┐
                  │              Mimir Distributor               │
                  └──────────────────────┬───────────────────────┘
                                         │
                   ┌─────────────────────┴─────────────────────┐
                   ▼ (Write Path)                              ▼ (Read Path)
      ┌─────────────────────────┐                 ┌─────────────────────────┐
      │     Mimir Ingester      │                 │  Mimir Query-Frontend   │
      └────────────┬────────────┘                 └────────────┬────────────┘
                   │ Metriken getrennt                         │ Abfrage mit Header:
                   │ nach Tenant-ID                            │ "tenant-a,infrastructure"
                   ▼                                           ▼
      ┌─────────────────────────┐                 ┌─────────────────────────┐
      │   Object Storage (S3)   │◄────────────────┤      Mimir Querier      │
      └─────────────────────────┘                 └────────────┬────────────┘
                   ▲                                           │
                   │ (Liest Rules & Configs)                   ▼
                   │                                          Grafana
      ┌────────────┴────────────┐                 ┌────────────┴────────────┐
      │       Mimir Ruler       ├────────────────►│    Mimir Alertmanager   │
      └─────────────────────────┘  Sendet Alerts  └────────────┬────────────┘
        Liest & evaluiert Rules    mit Header                  │ Routet Alerts an
        für "tenant-a"             "X-Scope-OrgID: tenant-a"   │ customer contact points
                                                               ▼
                                                  ┌─────────────────────────┐
                                                  │   Slack / Email / Web   │
                                                  └─────────────────────────┘
```

1. **Write Path (Distributor & Ingester):**
   Der Distributor empfängt die Daten, liest das `X-Scope-OrgID` aus und ordnet die Zeitreihen den Ingestern über einen zentralen Hash-Ring zu. Die Ingester halten die Daten im Speicher (getrennt nach Mandant) und schreiben sie periodisch in den S3-Storage.
2. **Read Path (Query-Frontend & Querier):**
   Das Query-Frontend empfängt Anfragen von Grafana. Es liest den Header `tenant-a,infrastructure` und teilt die PromQL-Abfrage auf. Der Querier lädt die relevanten Indizes und Blöcke beider Tenants aus dem S3-Speicher und führt die Abfrage aus.
3. **Ruler (Alert-Generierung):**
   Der Ruler lädt Alarmierungsregeln aus dem S3-Storage (MinIO/GCS Bucket `mimir-ruler`), die über die API pro Tenant abgelegt wurden. Er wertet die Alerts mandantenspezifisch aus. Triggert ein Alert, leitet der Ruler diesen an den Alertmanager weiter und setzt automatisch den Header `X-Scope-OrgID: tenant-a`.
4. **Alertmanager (Alarmierung & Benachrichtigung):**
   Der Alertmanager empfängt den Alert. Er lädt die Konfiguration von `tenant-a` aus dem S3-Bucket `mimir-alertmanager` und leitet den Alert an die konfigurierten Kanäle (z. B. Slack des Teams A) weiter.

### B. Ingester Hash-Ring vs. Shuffle Sharding
* **Consistent Hashing (Standard):** 
  Daten jedes Tenants werden über alle im StatefulSet verfügbaren Ingester verteilt. Dies maximiert die Auslastung, erhöht aber den "Blast Radius" (Ausfallbereich): Wenn ein Mandant das System überlastet, stürzen potenziell alle Ingester ab und reißen alle Mandanten mit sich.
* **Shuffle Sharding:** 
  Jedem Mandanten wird eine feste Teilmenge (z. B. 3 von 10 Ingestern) zugewiesen.
  * `Tenant-A` schreibt nur auf Ingester `1`, `4` und `8`.
  * `Tenant-B` schreibt nur auf Ingester `2`, `5` und `9`.
  Stürzt `Tenant-A` durch Kardinalitätsüberschreitung ab, sind die Pods von `Tenant-B` vollkommen sicher. Zudem spart dies massiv Arbeitsspeicher auf den einzelnen Pods, da sie nicht mehr alle Zeitreihen aller Mandanten im RAM halten müssen.

Konfiguration in Mimir:
```yaml
mimir-distributed:
  mimir:
    structuredConfig:
      limits:
        ingester_tenant_shard_size: 3
        store_gateway_tenant_shard_size: 3
```

### C. Storage-Struktur im S3/GCS-Bucket
Im Cloud Storage (MinIO, GCS oder AWS S3) werden die Metrik-Blöcke physikalisch nach Tenant-Präfixen getrennt:
```
gcs-bucket-mimir-blocks/
├── tenant-a/                ◄ Datenblöcke & Index von Mandant A
│   ├── 01J1ABCDE.../
│   └── debug/
├── tenant-b/                ◄ Datenblöcke & Index von Mandant B
│   └── 01J2KLMNO.../
└── infrastructure/          ◄ Globale K8s/Argo-Metriken (Tenant anonymous (oder Tenant 1))
    └── 01J3PQRST.../
```
* Dies ermöglicht das Festlegen von **IAM-Regeln auf Pfad-Ebene** (Service Account A darf nur auf `tenant-a/*` zugreifen) sowie mandantenspezifische Aufbewahrungsfristen (GCS Lifecycle Policies).

---

## 7. Vorteile für die Query-Performance

Die Mandantenfähigkeit erhöht nicht nur die Datensicherheit, sondern optimiert auch die Rechenleistung auf dem Lese-Pfad:
1. **Reduzierte Index-Größe:** 
   Bei einer Abfrage mit `X-Scope-OrgID: tenant-a` muss der Querier nicht den gesamten globalen Index durchsuchen, sondern lädt ausschließlich den Index von `tenant-a`. Da dieser um ein Vielfaches kleiner ist, werden Suchanfragen extrem beschleunigt und RAM-Ressourcen geschont.
2. **Fair-Share-Scheduling:** 
   Das Query-Frontend queued Abfragen pro Mandant. Riesige, ineffiziente Abfragen von Mandant B blockieren somit nicht die Abfrage-Pipelines von Mandant A.

---

## 8. Onboarding-Leitfaden für neue Kunden

Um einen neuen Mandanten (z. B. `Tenant-C`) hinzuzufügen, müssen folgende Schritte durchgeführt werden:

1. **SSO-Gruppe anlegen:** In Entra ID (oder GitHub) die Gruppe `Customer-C-Group` anlegen und die jeweiligen Benutzer hinzufügen.
2. **SSO-Mapping in Grafana konfigurieren:** In [noctua/values.yaml](file:///Users/saad.masood/Documents/Git/bwcloud-gitops/apps/grafana/noctua/values.yaml) das Mapping auf Org `4` eintragen:
   `org_mapping: "..., Customer-C-Group:4:Viewer"`
3. **Bootstrap-Skript erweitern:** In [grafana-bootstrap-script.yaml](file:///Users/saad.masood/Documents/Git/bwcloud-gitops/apps/grafana/noctua/templates/grafana-bootstrap-script.yaml) die Erstellung von Org `4` und deren Datenquellen (`tenant-c`) eintragen:
   ```sh
   create_org "Tenant-C" 4
   provision_datasources 4 "tenant-c"
   upload_dashboards 4
   ```
4. **Deployen:** Änderungen committen, pushen und in Argo CD synchronisieren. Der Pod-Neustart provisioniert die neue Umgebung vollautomatisch.

---

## 9. Sicherheitsanalyse & Einschränkungen

### 🔒 Sicherheit der Daten-Isolation
* **Strategie A Risiko:** Da die Kunden-Datenquelle den zusammengesetzten Header `tenant-a,infrastructure` sendet, hat der Client Zugriff auf den `infrastructure`-Tenant. Wenn der Kunde in Grafana die Rolle *Editor* oder Zugriff auf den *Explore-Tab* besitzt, kann er manuelle PromQL-Abfragen schreiben und z. B. `{namespace="tenant-b"}` abfragen. Liegen diese Metriken im globalen Tenant (wie z. B. cAdvisor-Metriken), kann er Daten anderer Mandanten sehen.
* **Gegenmaßnahme:** Kunden-Benutzer in Grafana per Standard auf die Rolle **Viewer** beschränken. Viewer können vordefinierte Dashboards betrachten, aber keine freien PromQL-Abfragen ausführen oder Dashboards verändern.

### 🔔 Isolation von Grafana-Alerts
* Da Grafana-Alerts strikt innerhalb des jeweiligen Organisations-Kontexts ausgeführt werden, sind Alert-Regeln, Benachrichtigungsziele (Slack-Webhooks) und Policies von Org 2 für Org 3 vollkommen unsichtbar.
* Alert-Auswertungen triggern über die jeweilige Datenquelle der Organisation und werten somit nur den erlaubten Mandantenscope aus.
