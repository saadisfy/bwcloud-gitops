# 🚀 Grafana How-To: Multi-Tenancy & RBAC in Grafana Open Source (OSS)

Dieses Dokument bietet einen detaillierten Leitfaden zur Umsetzung von **Multi-Tenancy** und **RBAC** in der Open-Source-Version von Grafana (OSS) ohne den Einsatz von Grafana Enterprise oder Grafana Cloud. Es erklärt die Architektur, die OAuth-Integration (Microsoft Entra ID & GitHub), das dynamische API-Bootstrapping sowie bewährte Onboarding-Workflows.

---

## 📖 Inhaltsverzeichnis
1. [Problemstellung & Architektur](#1-problemstellung--architektur)
2. [Die 3 Säulen der OSS Multi-Tenancy](#2-die-3-säulen-der-oss-multi-tenancy)
3. [Schritt-für-Schritt-Implementierung](#3-schritt-für-schritt-implementierung)
4. [SSO-Anbindung & Org-Mapping](#4-sso-anbindung--org-mapping)
5. [Onboarding-Leitfaden für neue Kunden](#5-onboarding-leitfaden-für-neue-kunden)
6. [Sicherheitsanalyse & Einschränkungen](#6-sicherheitsanalyse--einschränkungen)

---

## 1. Problemstellung & Architektur

In Enterprise-Umgebungen fordern Kunden und Teams eine strikte Trennung ihrer Daten. Grafana Enterprise löst dies über feingranulare Zugriffsrechte (RBAC) und Teams. In **Grafana OSS** fehlen diese Features auf Datenquellen- und Dashboard-Ebene.

Unsere Lösung nutzt native Grafana OSS-Mechanismen in Kombination mit einer automatisierten API-Provisionierung:
* **Grafana-Organisationen (Orgs):** Jede Organisation ist ein vollständig isolierter logischer Kontext (eigene Dashboards, Alert-Regeln und Datenquellen).
* **Mimir/Loki Multi-Tenancy:** Prometheus Mimir und Grafana Loki trennen Daten physikalisch über den HTTP-Header `X-Scope-OrgID`.
* **Tenant-spezifische Datenquellen:** Jede Grafana-Org erhält eine Datenquelle, die Abfragen automatisch mit dem Header `X-Scope-OrgID: <kunden-tenant>` versieht.
* **SSO-Gruppenmapping:** Über Microsoft Entra ID (oder GitHub) werden Benutzer anhand ihrer Gruppenzugehörigkeit beim Login automatisch in die richtige Grafana-Org geleitet.

---

## 2. Die 3 Säulen der OSS Multi-Tenancy

Da Grafana OSS das Erstellen von Orgs und Datenquellen für Orgs $> 1$ nicht über YAML-Dateien (Provisioning) unterstützt, ohne beim Start abzustürzen, haben wir das Problem über drei Säulen gelöst:

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

1. **Datei-basiertes Provisioning (nur für Org 1):** Verhindert Startabstürze.
2. **K8s Sidecar:** Erkennt Dashboard-ConfigMaps und spiegelt sie im Verzeichnis `/tmp/dashboards` wider.
3. **Bootstrap-API-Skript:** Erstellt nach dem Start des Pods die Orgs, provisioniert Datenquellen und kopiert Dashboards via API.

---

## 3. Schritt-für-Schritt-Implementierung

### Schritt 1: Das Bootstrap-Skript (ConfigMap)
Wir deployen das Skript als Kubernetes-ConfigMap. Es liegt im Helm-Chart unter:
`apps/grafana/noctua/templates/grafana-bootstrap-script.yaml`

Das Skript führt folgende Schritte aus:
1. Wartet auf die Erreichbarkeit der Grafana-API unter `http://localhost:3000`.
2. Setzt das Admin-Passwort auf den aktuellen Wert von `$GF_SECURITY_ADMIN_PASSWORD` (idempotent).
3. Erstellt die Organisationen `Tenant-A` (Org-ID `2`) und `Tenant-B` (Org-ID `3`).
4. Erstellt die Mimir-, Loki-, Tempo- und Alertmanager-Datenquellen in den jeweiligen Orgs und injectet den Header `X-Scope-OrgID` (z. B. `tenant-a,infrastructure`).
5. Liest alle vom Sidecar heruntergeladenen JSON-Dashboards aus `/tmp/dashboards` und lädt sie in die Kunden-Orgs hoch.

### Schritt 2: Einbinden des Skripts in Helm Values
In den Helm-Values aktivieren wir den Sidecar, hängen die ConfigMap als Volume ein und definieren den `postStart`-Lifecycle-Hook.

**In `apps/grafana/base/values.yaml`:**
```yaml
grafana:
  # 1. Background Execution des Bootstrap-Skripts
  lifecycleHooks:
    postStart:
      exec:
        command:
          - /bin/sh
          - -c
          - '/bin/sh /opt/bootstrap/bootstrap.sh &'

  # 2. Sidecar für Dashboard-ConfigMaps aktivieren
  sidecar:
    dashboards:
      enabled: true
      label: app.kubernetes.io/component
      labelValue: dashboard
```

**In `apps/grafana/noctua/values.yaml`:**
```yaml
grafana:
  # 3. Mount der ConfigMap als Volume
  extraConfigmapMounts:
    - name: grafana-bootstrap-script
      mountPath: /opt/bootstrap
      configMap: grafana-bootstrap-script
      readOnly: true
```

---

## 4. SSO-Anbindung & Org-Mapping

### A. Microsoft Entra ID (Azure AD)
Microsoft Entra ID liefert Gruppenmitgliedschaften als Array im Token-Claim `groups` oder `roles`. 

In der `grafana.ini` (Generic OAuth) wird das dynamische Mapping wie folgt konfiguriert:
```yaml
grafana:
  grafana.ini:
    auth.generic_oauth:
      enabled: true
      name: Microsoft Entra ID
      allow_sign_up: true
      client_id: $__env{GF_AUTH_GENERIC_OAUTH_CLIENT_ID}
      client_secret: $__env{GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET}
      scopes: openid email profile offline_access
      auth_url: https://login.microsoftonline.com/$__env{GF_AUTH_GENERIC_OAUTH_TENANT_ID}/oauth2/v2.0/authorize
      token_url: https://login.microsoftonline.com/$__env{GF_AUTH_GENERIC_OAUTH_TENANT_ID}/oauth2/v2.0/token
      api_url: https://graph.microsoft.com/oidc/userinfo
      
      # Weist Rollen basierend auf Entra ID App-Roles zu
      role_attribute_path: "contains(roles, 'GrafanaAdmin') && 'Admin' || contains(roles, 'GrafanaEditor') && 'Editor' || 'Viewer'"
      role_attribute_strict: true
      
      # Liest das 'groups'- oder 'roles'-Array aus dem Token aus
      org_attribute_path: roles || groups
      
      # Mapping-Format: <EntraID_Group_Object_ID_oder_Name>:<GrafanaOrgID>:<GrafanaRolle>
      org_mapping: "Customer-A-Group-ID:2:Viewer, Customer-B-Group-ID:3:Viewer, Observability-Admin-Group-ID:1:Admin"
```

### B. GitHub OAuth
Bei GitHub authentifiziert sich der Nutzer über GitHub-Organisationen und -Teams.

```yaml
grafana:
  grafana.ini:
    auth.github:
      enabled: true
      name: GitHub
      allow_sign_up: true
      scopes: user:email,read:org # read:org wird zwingend für Teams benötigt!
      client_id: $__env{GF_AUTH_GITHUB_CLIENT_ID}
      client_secret: $__env{GF_AUTH_GITHUB_CLIENT_SECRET}
      role_attribute_path: "login == 'saadisfy' && 'Admin' || 'Viewer'"
      role_attribute_strict: true
      skip_org_role_sync: false
      
      # Mapping-Format: <GitHubOrg>/<GitHubTeam>:<GrafanaOrgID>:<GrafanaRolle>
      org_mapping: "saadisfy-org/team-a:2:Viewer, saadisfy-org/team-b:3:Viewer"
```

---

## 5. Onboarding-Leitfaden für neue Kunden

Wenn ein neuer Kunde (z. B. `Tenant-C`) hinzukommt, folge diesen Schritten:

### Schritt 1: SSO-Gruppe erstellen
Lasse das IAM/AD-Team die entsprechende Entra ID-Gruppe (oder das GitHub-Team) erstellen, z. B. `Customer-C-Group`.

### Schritt 2: Werte in GitOps-Repository eintragen
Erweitere das `org_mapping` in [noctua/values.yaml](file:///Users/saad.masood/Documents/Git/bwcloud-gitops/apps/grafana/noctua/values.yaml) um den neuen Mapping-Eintrag (z. B. auf Org-ID `4`):

```yaml
# Unter auth.generic_oauth bzw. auth.github:
org_mapping: "Customer-A-Group:2:Viewer, Customer-B-Group:3:Viewer, Customer-C-Group:4:Viewer"
```

### Schritt 3: Bootstrap-Skript erweitern
Füge im ConfigMap-Template [grafana-bootstrap-script.yaml](file:///Users/saad.masood/Documents/Git/bwcloud-gitops/apps/grafana/noctua/templates/grafana-bootstrap-script.yaml) die Befehle zum Anlegen des neuen Tenants hinzu:

```sh
# Org 4 erstellen
create_org "Tenant-C" 4

# Datenquellen für Org 4 provisionieren (nutzt Mimir-Tenant "tenant-c" + Shared "infrastructure")
provision_datasources 4 "tenant-c"

# Dashboards in Org 4 hochladen
upload_dashboards 4
```

### Schritt 4: Sync & Deployment
Commite und pushe die Änderungen in deinen GitOps-Branch (`main`).
1. Argo CD zieht die Änderungen automatisch oder wird manuell gesynct.
2. Der **Stakater Reloader** erkennt die Änderung der ConfigMap und führt einen automatischen Rolling Restart des Grafana-Pods durch.
3. Nach dem Start läuft das Bootstrap-Skript an, erstellt die Org `4`, richtet die Datenquellen ein und kopiert die Dashboards.
4. Der Kunde kann sich sofort einloggen.

---

## 6. Sicherheitsanalyse & Einschränkungen

### 🔒 Sicherheit der Daten-Isolation (Strategie A)
* **Wie es funktioniert:** Datenquellen senden den Header `X-Scope-OrgID: tenant-a,infrastructure`. Mimir und Loki erlauben das parallele Abfragen beider Tenants.
* **Risiko in Grafana OSS:** Wenn der Kunde in Grafana "Explore"-Rechte besitzt oder Dashboards editieren darf, kann er in PromQL das Namespace-Filter manuell auf ein fremdes Label ändern (z. B. `{namespace="tenant-b"}`). Da er über die Datenquelle Zugriff auf das gesamte Mimir-Gateway hat, würde Mimir die Daten zurückliefern, sofern sie im `infrastructure`-Tenant liegen.
* **Empfehlung:** Vergib an Kunden-Accounts in Grafana standardmäßig nur die Rolle **Viewer** (Leserechte auf Dashboards, kein Zugriff auf den "Explore"-Tab).

### 🔔 Isolation von Grafana-Alerts
Da Alerts in Grafana OSS strikt innerhalb des jeweiligen Organisations-Kontexts ausgeführt werden:
* **Keine Leaks:** Alert-Regeln, Contact Points (z.B. Slack-Webhooks) und Notification Policies von Org 2 (`Tenant-A`) sind für Org 3 (`Tenant-B`) vollkommen unsichtbar.
* **Sichere Auswertung:** Alerts, die in Org 2 definiert sind, werten die Datenquelle von Org 2 aus. Sie haben somit keinen Zugriff auf Daten anderer Kunden.
