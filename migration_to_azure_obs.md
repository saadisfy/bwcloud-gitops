# Migration Plan: `noctua` (Baremetal) -> Azure Cluster `obs`

Dieser Plan ist auf den aktuellen Repo-Stand ausgelegt (ApplicationSets in `appsets/`, Bootstrap in `0day-deployment-manifests/`) und beschreibt einen kontrollierten Umzug auf einen leeren Azure-Cluster.

---

## 1) Ziel, Annahmen, Strategie

## Ziel
- GitOps-Stack vollständig auf AKS (`kubectx obs`) betreiben.
- Argo CD bleibt Source of Truth und deployt weiterhin aus `main`.
- Minimaler Ausfall für öffentliche Endpunkte (`*.saadisfy.me`).

## Annahmen
- Zielcluster ist leer.
- DNS-Zone `saadisfy.me` kann umgeschaltet werden.
- Ingress bleibt nginx-basiert, TLS via cert-manager/ClusterIssuer `letsencrypt-prod`.

## Empfohlene Strategie
- **Phasenweise Neuaufbau + kontrollierter Cutover** statt „Lift&Shift auf Dateisystemebene“.
- Stateful Teile (v. a. Mimir, optional Grafana DB) bewusst separat behandeln.

---

## 2) Inventar der aktuell deployten GitOps-Applikationen

Basierend auf `appsets/*.yaml` (prod).

| AppSet / App | Namespace | Typ | Zustand / Daten | Wichtige Abhängigkeiten |
|---|---|---|---|---|
| `argocd` | `argocd` | Helm Wrapper (`apps/argocd/prod`) | Control Plane, Secret-abhängig | GitHub Repo-Zugang, SSO-Secrets |
| `cluster-priority` | `kube-system` | Raw manifests (`apps/cluster-priority/prod`) | stateless | keine |
| `reloader` | `reloader` | Helm Wrapper | stateless | keine |
| `istio` | `istio-system` | Helm Wrapper (`base` + `istiod`) | stateless Control Plane | optional für Mesh-Namespaces |
| `mimir` | `mimir` | Helm Wrapper (`mimir-distributed`) | **stateful** (PVCs, filesystem backend) | StorageClass, Ingress, cert-manager |
| `alloy` | `alloy` | Helm Wrapper (DaemonSet + KSM + Node Exporter) | stateless (Queue tmp) | Mimir erreichbar |
| `grafana` | `grafana` | Helm Wrapper + Operator CRs | teilweise stateful (PVC) | Mimir, Admin/OAuth-Secrets |
| `otel-operator` | `otel-operator` | Helm Wrapper + Collector/Instrumentation CRs | stateless | cert-manager webhook, Mimir |
| `spring-petclinic` | `spring-petclinic` | Custom Helm | stateless App | otel-operator (Annotation), Ingress |
| `opentelemetry-demo` | `opentelemetry-demo` | Helm Wrapper | stateless Demo | Ingress |
| `kargo` | `kargo` | Helm Wrapper (OCI) | stateless + Secret-abhängig | Git write creds, Ingress |
| `kargo-projects` | mehrere (`kargo-projects`, `spring-petclinic`, `grafana`) | CRs (Project/Stage/Warehouse) | CR-Status | Kargo API + Git creds |

---

## 3) Vorbereitungen vor dem ersten Deploy auf `obs`

1. **Freeze-Fenster definieren**
   - Keine großen Änderungen während Migration.
   - Kargo Promotions pausieren (kein Auto-Push parallel).

2. **DNS-Strategie festlegen**
   - Empfohlen: TTL vorab senken (z. B. 60s), dann Cutover auf neue Ingress IP.
   - Alternativ temporäre Azure-Subdomains für Paralleltest.

3. **Backup/Export vom Quellcluster (`noctua`)**
   - Manuell gesetze Secrets sichern (Argo CD/Grafana/Kargo/SSO/Repo-Creds).
   - Optional: Grafana PVC sichern (falls lokale DB/State mitgenommen werden soll).
   - Entscheidung zu Mimir-Historie treffen (siehe Abschnitt Mimir).

4. **AKS-Basis bereitstellen (manuell, nicht durch dieses Repo)**
   - nginx Ingress Controller
   - cert-manager + `ClusterIssuer` `letsencrypt-prod`
   - funktionierende Default `StorageClass` (ReadWriteOnce PVCs)
   - (optional) ExternalDNS für automatisches DNS-Management

---

## 4) Argo CD -> GitHub Zugriff: Empfehlung und Umsetzung

Das Repo enthält bereits PAT-basiertes Bootstrap (`0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml.example`). Für Azure-Migration solltest du entscheiden:

## Option A (schnell, kompatibel mit aktuellem Repo): Fine-grained PAT
- Secret wie im Template anlegen (`repo-bwcloud-gitops`).
- Scope minimal:
  - Repository: `bwcloud-gitops`
  - **Contents: Read** (für Argo CD)
  - Falls Kargo in dasselbe Repo schreibt: zusätzlich separater Write-Token für Kargo verwenden.

## Option B (empfohlen langfristig): GitHub App
- Besser rotierbar, feinere Rechte, kein User-PAT.
- Rechte für Argo CD:
  - Repository permissions: `Contents: Read`, `Metadata: Read`
- Argo CD Repo-Secret mit GitHub-App-Feldern anlegen (statt username/password).

> Empfehlung: **Argo CD Read-only** und **Kargo Write separat** (eigene Credentials), damit Deployment und Promotion sauber getrennt sind.

---

## 5) Bootstrap-Sequenz auf Azure (`obs`)

## Reihenfolge (manuell)
1. Kontext setzen: `kubectx obs`
2. Argo CD initial installieren (Bootstrap außerhalb dieses Repos, falls noch nicht vorhanden).
3. Argo CD Git-Repo Zugriff setzen:
   - `0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml` (PAT) **oder** GitHub-App Secret.
4. Helm-Repo-Secrets setzen:
   - `0day-deployment-manifests/argocd-helm-repos.yaml`
5. Manuelle App-Secrets setzen:
   - `app-admin-secrets.yaml` (aus Example ableiten)
   - `grafana-secrets.yaml` (aus Example ableiten)

6. Root-App anwenden:
   - `0day-deployment-manifests/root-application.yaml`
7. ApplicationSets erscheinen in Argo CD.
8. Apps in definierter Reihenfolge synchronisieren (siehe Abschnitt 6).

---

## 6) Migrationsplan pro Applikation (inkl. manueller Eingriffe)

Hinweis: Viele AppSets haben **kein** `syncPolicy.automated`; initialer Sync muss aktiv gesteuert werden.

## 6.1 `cluster-priority` (Namespace `kube-system`)
**Zweck:** PriorityClasses (`argocd-critical`, `metallb-critical`).

**Vorgehen**
- Früh synchronisieren (vor Argo CD Self-Management).

**Manuell prüfen**
- `metallb-critical` ist auf AKS i. d. R. unkritisch, auch wenn MetalLB nicht genutzt wird.

---

## 6.2 `argocd` (Namespace `argocd`)
**Zweck:** Self-managed Argo CD.

**Vorgehen**
- Nach Repo-/Helm-/Secret-Bootstrap synchronisieren.
- Prüfen, ob Ingress/URL (`argocd.saadisfy.me`) in Azure erreichbar ist.

**Manuelle Eingriffe**
- `argocd-secret` Inhalte (Admin bcrypt + `server.secretkey`) müssen gesetzt sein.
- OAuth Secret `argocd-github-oauth` muss vorhanden sein, wenn SSO genutzt wird.
- DNS/Ingress/TLS muss auf AKS zeigen.

---

## 6.3 `reloader` (Namespace `reloader`)
**Zweck:** automatische Rollouts bei Secret/ConfigMap Änderungen.

**Vorgehen**
- Früh synchronisieren, damit spätere Secret-Änderungen sauber ausgerollt werden.

**Manuell**
- Keine besonderen Datenmigrationen.

---

## 6.4 `istio` (Namespace `istio-system`)
**Zweck:** Control Plane (`base` + `istiod`), aktuell ohne globales Mesh-Enforcement.

**Vorgehen**
- Nach Basisplattform synchronisieren.
- Webhook-`ignoreDifferences` ist bereits in `appsets/istio.yaml` gesetzt.

**Manuell**
- Falls später Mesh in App-Namespaces aktiviert wird: Namespace-Onboarding + Rollouts separat planen.
- Aktuell kein Istio-CNI im Repo; bei restriktiven Policies ggf. gesondert bewerten.

---

## 6.5 `mimir` (Namespace `mimir`) – **kritisch/stateful**
**Zweck:** Metrics Backend mit PVCs und filesystem/local Backends.

**Vorgehen**
- Vor Grafana/Alloy deployen.
- Prüfen, dass StorageClass auf AKS ausreichende Performance hat.

**Manuelle Eingriffe / Entscheidungen**
- **Historische Datenmigration:** Bei aktuellem filesystem/local Setup aufwändig.
  - Option 1 (einfach): „fresh start“ auf Azure (keine Historie).
  - Option 2 (aufwändig): PVC-Inhalte konsistent migrieren (Downtime + Kopierstrategie).
  - Option 3 (langfristig besser): vor Migration auf Object Storage (z. B. Blob/S3-kompatibel) umstellen, dann Cutover vereinfachen.
- Ingress Hosts:
  - `mimir.saadisfy.me`
  - `mimir-query.saadisfy.me`

---

## 6.6 `alloy` (Namespace `alloy`)
**Zweck:** Metrics Scraping (DaemonSet, hostNetwork) und Export nach Mimir.

**Vorgehen**
- Nach Mimir synchronisieren.

**Manuell**
- Auf AKS prüfen, ob `hostNetwork: true` policyseitig erlaubt ist.
- Node-spezifische Scrapes (kubelet/cadvisor) auf AKS validieren.

---

## 6.7 `grafana` (Namespace `grafana`)
**Zweck:** UI + Operator CRs, Datasources zeigen auf Mimir Services.

**Vorgehen**
- Nach Mimir synchronisieren.
- OAuth und Admin Secret vorher anwenden.

**Manuelle Eingriffe**
- `grafana-admin-credentials` Secret zwingend.
- `grafana-secrets` Secret für GitHub Login & SMTP.
- Ingress/TLS/DNS (`grafana.saadisfy.me`) auf AKS.
- Optional PVC-Migration (falls DB/State erhalten bleiben soll).

---

## 6.8 `otel-operator` (Namespace `otel-operator`)
**Zweck:** Operator + `OpenTelemetryCollector` + `Instrumentation` CRs.

**Vorgehen**
- Vor instrumentierten Apps synchronisieren (`spring-petclinic`).

**Manuell**
- cert-manager muss laufen (Webhook Certs in base values auf cert-manager gesetzt).
- Collector Endpoint zu Mimir (`mimir-distributor...:8080/otlp`) erreichbar prüfen.

---

## 6.9 `spring-petclinic` (Namespace `spring-petclinic`)
**Zweck:** Beispiel-App mit Java Auto-Instrumentation Annotation.

**Vorgehen**
- Nach `otel-operator` synchronisieren.

**Manuell**
- Ingress Host `spring-petclinic.saadisfy.me` (aktuell ohne TLS).
- Falls privates Image genutzt wird: `imagePullSecrets` bereitstellen.

---

## 6.10 `opentelemetry-demo` (Namespace `opentelemetry-demo`)
**Zweck:** Demo-Workload (teilweise Komponenten deaktiviert in prod).

**Vorgehen**
- Nach Plattformbasis synchronisieren.

**Manuell**
- Ingress Host `opentelemetry-demo.saadisfy.me` (aktuell ohne TLS).
- Ressourcenbedarf beobachten (Demo kann bei kleinem AKS SKU eng werden).

---

## 6.11 `kargo` (Namespace `kargo`)
**Zweck:** Promotion Engine.

**Vorgehen**
- Nach Argo CD und Git-Zugriff synchronisieren.

**Manuelle Eingriffe**
- `kargo-api` Secret manuell patchen (Admin Hash + Signing Key) gemäß `app-admin-secrets.yaml.example`.
- Ingress/TLS `kargo.saadisfy.me`.
- Für echte Promotions: Git-Write Credentials in Kargo bereitstellen (separat von Argo CD Read-Creds).

---

## 6.12 `kargo-projects` (mehrere Namespaces)
**Zweck:** `Project`/`Warehouse`/`Stage` CRs für Kargo.

**Vorgehen**
- Erst nach laufendem `kargo` synchronisieren.

**Manuell**
- Prüfen, ob Ziel-Namespaces (`spring-petclinic`, `grafana`, `kargo-projects`) vorhanden sind.
- Prüfen, ob Warehouses auf Git/Image registries zugreifen können (auth ggf. nötig).
- In diesem Repo sind einige dev/int Dateien absichtlich als leere `List` vorhanden; prod-Pfade und Excludes beachten.

---

## 7) Empfohlene Sync-Reihenfolge (auf Azure)

1. `cluster-priority`
2. `argocd` (self-managed stabilisieren)
3. `reloader`
4. `istio`
5. `mimir`
6. `alloy`
7. `grafana`
8. `otel-operator`
9. `spring-petclinic`
10. `opentelemetry-demo`
11. `kargo`
12. `kargo-projects`

---

## 8) Cutover-Plan (DNS + Traffic)

1. AKS-Stack vollständig bis `Healthy`.
2. Smoke-Tests pro URL (Argo CD, Grafana, Mimir, Kargo, Apps).
3. DNS auf neue Ingress-IP umstellen (`*.saadisfy.me`).
4. Beobachten:
   - Ingress 4xx/5xx
   - Argo CD Sync Health
   - Mimir Ingestion
   - Grafana Datasource Health
5. Erst nach Stabilität: alte Workloads auf `noctua` kontrolliert stilllegen.

---

## 9) Rollback-Strategie

- Solange DNS nicht umgestellt ist: Risiko gering, einfach weiter auf `noctua`.
- Nach DNS-Cutover:
  - DNS zurück auf alte Ingress-IP (TTL niedrig halten).
  - Promotions/Kargo auf Azure pausieren, um Divergenz in Git zu vermeiden.
- Bei Mimir-Datenproblemen:
  - temporär ohne Historie weiterfahren oder Rollback auf alten Cluster.

---

## 10) Konkrete manuelle Artefakte/Dateien (Checkliste)

Aus diesem Repo:
- `0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml` (lokal aus Example erzeugen, gitignored)
- `0day-deployment-manifests/argocd-helm-repos.yaml`
- `0day-deployment-manifests/app-admin-secrets.yaml` (lokal aus Example)
- `0day-deployment-manifests/grafana-secrets.yaml` (lokal aus Example)
- `0day-deployment-manifests/root-application.yaml`

Außerhalb dieses Repos (manuell auf AKS):
- ingress-nginx Installation
- cert-manager + `ClusterIssuer` `letsencrypt-prod`
- DNS Umschaltung
- ggf. GitHub App/PAT Erzeugung und Rotation

---

## 11) Offene Entscheidungen vor Start

1. **Mimir Historie mitnehmen oder neu starten?**  
2. **Argo CD Repo Auth via PAT (kurzfristig) oder GitHub App (langfristig)?**  
3. **Gleiche Domains sofort cutovern oder temporäre Azure-Subdomains für Parallelbetrieb?**  
4. **Kargo direkt aktivieren oder erst nach stabiler Basis (empfohlen: später)?**

---

Wenn du willst, kann daraus als nächster Schritt ein **konkretes Execution-Runbook mit exakten `kubectl`/`argocd` Kommandos pro Phase** erstellt werden (inkl. Go/No-Go Kriterien je Gate).
