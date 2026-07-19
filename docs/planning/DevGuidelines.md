
# Geplanter Entwicklungsprozess (Label-based Preview)

## Ziel

Entwickler testen Änderungen an einzelnen Observability-Apps ohne die produktiven Stage-Ordner zu verändern. Jede Änderung wird als isoliertes Preview Deployment im eigenen Namespace erzeugt. Nach Merge landet die Änderung automatisch in der normalen Dev Stage. Danach übernimmt Kargo.

## Branching Strategy: Trunk-Based Development

Dieser Workflow folgt **Trunk-Based Development** mit kurzlebigen Feature Branches.

### Was ist Trunk-Based Development?

**Trunk-Based Development**:
- Ein zentraler Branch (`master`/`main`) ist die Source of Truth
- Feature Branches sind **kurzlebig** (max. 1-3 Tage)
- Direkter Merge nach `master` nach Review
- Alle Entwickler arbeiten nahe am Trunk
- Continuous Integration in den Hauptbranch

**Im Gegensatz zu klassischem Feature-Branch Development**:
- Langlebige Feature Branches (Wochen/Monate)
- Separate `develop` Branch für Integration
- Separate `release` Branches für Vorbereitung
- Komplexe Merge-Strategie zwischen Branches
- Höheres Risiko für Merge-Konflikte

### Warum keine `dev` und `release` Branches?

In diesem GitOps-Setup werden **Deployment Stages durch Kargo verwaltet, nicht durch Git Branches**:

```
Git Branches (Code):           Deployment Stages (Infrastructure):
    master                            ↓
       ↓                        ┌──────────────┐
    (Code)                      │  Dev Stage   │ ← master HEAD
                                └──────────────┘
                                       ↓
                                 (Kargo Promotion)
                                       ↓
                                ┌──────────────┐
                                │  Int Stage   │ ← v1.2.0-rc.1 Tag
                                └──────────────┘
                                       ↓
                                 (Kargo Promotion)
                                       ↓
                                ┌──────────────┐
                                │  Prod Stage  │ ← v1.2.0 Tag
                                └──────────────┘
```

**Gründe gegen `dev`/`release` Branches**:

1. **Separation of Concerns**
   - Git verwaltet Code-Versionen
   - Kargo verwaltet Deployment-Promotions
   - Klare Verantwortlichkeiten

2. **Vermeidung von Branch-Chaos**
   ```
   ❌ Klassisch (kompliziert):
   feature → develop → release/v1.2 → master
              ↓           ↓            ↓
            Dev Env    Int Env      Prod Env

   ✅ Trunk-based + Kargo (einfach):
   feature → master
              ↓
   Dev Stage → Int Stage → Prod Stage (via Kargo)
   ```

3. **Keine Merge-Konflikte zwischen Stages**
   - `develop` Branch sammelt alle Features → häufige Konflikte
   - `release` Branches benötigen Backports → Fehleranfällig
   - Mit Trunk-based: Ein Merge, eine Source of Truth

4. **GitOps-Prinzip**
   - Git beschreibt **WAS** deployed wird (Code)
   - Kargo entscheidet **WO** es deployed wird (Stage)
   - Tags markieren Release-Punkte, nicht Branches

5. **Schnellere Feedback-Loops**
   - Nach Merge sofort in Dev Stage testbar
   - Kein Warten auf `develop` → `release` Merge
   - Preview Deployments für Pre-Merge Testing

6. **Einfachere Hotfixes**
   ```
   ❌ Mit release Branch:
   hotfix → master → cherry-pick zu release/v1.2 → deploy

   ✅ Mit Trunk-based + Kargo:
   hotfix → master → Tag v1.2.1 → Kargo promote zu Prod
   ```

### Feature Branch Lifecycle

Feature Branches sind **kurzlebig und disposable**:

```
Tag 1: Branch erstellt, MR opened (Draft), Preview deployed
Tag 2: Entwicklung, Testing in Preview
Tag 3: MR Ready, Review, Merge → Branch gelöscht
```

**Best Practices**:
- Feature Branch max. 2-3 Tage offen
- Kleine, atomare Changes
- Squash Merge für saubere History
- Branch wird nach Merge gelöscht

### Vergleich: Klassisch vs. Dieses Setup

**❌ Klassischer Git-Flow (kompliziert)**:

```
feature/sre-500 ──┐
                  ├──> develop ──┐
feature/sre-501 ──┘               │
                                  ├──> release/v1.2 ──> master ──> Tag v1.2.0
                  ┌───────────────┘         │
hotfix/urgent ────┴───────────────────────> master ──> Tag v1.2.1
                                            
Deployment:
develop     → Dev Environment
release/v1.2 → Int Environment  
master      → Prod Environment

Probleme:
- 3 langlebige Branches zu synchronisieren
- Cherry-picks zwischen release und master
- Merge-Konflikte bei Hotfixes
- Unklar welche Version wo läuft
```

**✅ Trunk-Based + GitOps (einfach)**:

```
feature/sre-500 ──┐
                  ├──> master (HEAD) ──> Tag v1.2.0-rc.1 ──> Tag v1.2.0
feature/sre-501 ──┘       │                    │                  │
                          │                    │                  │
hotfix/urgent ────────────┘                    │                  │
                                               │                  │
Deployment via Kargo:                          │                  │
master HEAD     → Dev Stage                    │                  │
Tag v1.2.0-rc.1 → Int Stage ───────────────────┘                  │
Tag v1.2.0      → Prod Stage ─────────────────────────────────────┘

Vorteile:
+ Ein Branch (master) als Source of Truth
+ Tags markieren Release-Punkte
+ Kargo verwaltet Stage Promotions
+ Klare Trennung: Code (Git) vs. Deployment (Kargo)
+ Keine Merge-Konflikte zwischen Stages
```

---

## Semantic Versioning & Tagging im GitOps-Kontext

### Warum Semantic Versioning?

Dieses Setup nutzt **Semantic Versioning (SemVer 2.0)**, weil es der De-facto Standard im Kubernetes- und Helm-Ökosystem ist:

**1. Helm Chart Kompatibilität**

Helm Charts erwarten SemVer für zwei Felder:

```yaml
# Chart.yaml
apiVersion: v2
name: grafana
version: 1.2.0        # Chart Version (SemVer)
appVersion: 1.2.0     # Application Version (SemVer)
```

Helm nutzt SemVer für:
- Dependency Resolution (`dependencies[].version: "^1.2.0"`)
- Upgrade/Rollback Logic
- Repository Indexing
- Version Constraints

**2. Kubernetes Standards**

Kubernetes-Ökosystem nutzt SemVer für:
- Container Image Tags (`grafana:1.2.0`)
- Operator Versioning
- CRD Versioning (`apiVersion: v1`)
- Tooling (Kustomize, ArgoCD, Flux)

**3. GitOps Best Practices**

SemVer ermöglicht:
- Automatische Promotion Rules in Kargo
- Semantic Release Pipelines
- Automatische Changelog Generation
- Dependency Tracking

### Warum Tags, wenn Helm Charts direkt deployed werden?

**Berechtigte Frage**: Wenn ArgoCD die Helm Charts direkt aus Git deployed und wir keine externen Consumers haben, wozu taggen?

**Antwort**: Tags sind die **Markierungen für kontrollierte Promotions** zwischen Stages.

#### 1. Kargo Promotion Tracking

Kargo benötigt **stabile Referenzen** für Stage Promotions:

```yaml
# Kargo verfolgt WELCHE Version in WELCHER Stage läuft

Dev Stage:      master HEAD (sha-abc123)  ← kontinuierlich updated
                ↓
Int Stage:      v1.2.0-rc.1 (sha-abc123)  ← stabiler Tag
                ↓
Prod Stage:     v1.2.0 (sha-def456)       ← stabiler Tag
```

**Ohne Tags**:
```
❌ Problem: "Promote commit abc123 from Dev to Int"
   → Welche Features sind in abc123?
   → Was ist der Unterschied zu xyz789?
   → Unklar für Audit/Compliance
```

**Mit Tags**:
```
✅ Lösung: "Promote v1.2.0-rc.1 from Dev to Int"
   → Klar definierte Version
   → Changelog verfügbar
   → Audit Trail nachvollziehbar
```

#### 2. Helm Chart Versioning

Auch wenn Charts direkt aus Git kommen, muss `Chart.yaml` versioniert sein:

```yaml
# charts/grafana/Chart.yaml
version: 1.2.0        # ← Diese Version kommt vom Git Tag
appVersion: 1.2.0     # ← Gleiches Tag

# Warum wichtig?
# - Helm History zeigt Versions
# - Rollback: helm rollback grafana 3 (zu Version 1.1.9)
# - Helm List zeigt deployed Version
```

**Helm History Beispiel**:
```bash
$ helm history grafana -n prod
REVISION  VERSION   STATUS      DESCRIPTION
1         1.1.9     superseded  Install complete
2         1.2.0-rc.1 superseded  Upgrade complete
3         1.2.0     deployed    Upgrade complete
```

Ohne korrekte Versionierung: Alle Revisions zeigen "0.1.0" → nutzlos für Debugging.

#### 3. Container Image Tags

Git Tags steuern Container Image Tags:

```yaml
# CI Pipeline
Git Tag: v1.2.0
         ↓
Container Image: registry.gitlab.com/org/grafana:1.2.0
                                                  ↓
# values.yaml
image:
  tag: "1.2.0"  # ← Muss exakte Version sein für Prod
```

**Warum nicht `latest` in Prod?**
- `latest` ist ein moving target
- Rollback unmöglich (`latest` wurde überschrieben)
- Kein Audit Trail welches Image deployed war
- Compliance-Probleme

#### 4. Rollback-Punkte

Tags sind **getestete, stabile Rollback-Punkte**:

```bash
# Production läuft v1.2.0
# Problem entdeckt

# Kargo Rollback zu v1.1.9 (letzter stabiler Tag)
# NICHT zu "master 5 commits zurück" (instabil, ungetestet)
```

**Vorteil**: Jeder Tag wurde in Int Stage getestet, bevor er nach Prod promoted wurde.

#### 5. Audit Trail & Compliance

Für regulierte Umgebungen (Bank, Healthcare, Finance):

```
Audit-Frage: "Welche Version lief am 15.11.2024 in Production?"

Mit Tags:
✅ v1.1.9 (deployed 10.11.2024 - 20.11.2024)
   Git Tag: v1.1.9
   Container Images: grafana:1.1.9, prometheus:2.45.0
   Helm Chart Version: 1.1.9
   Deployment Manifest: Git commit def456
   Changelog: verfügbar
   Approvals: Tech Lead + Product Owner

Ohne Tags:
❌ "master commit abc123... irgendwas zwischen abc123 und xyz789"
   → Keine klare Version
   → Kein Changelog
   → Compliance Audit failed
```

#### 6. Automatische Changelog Generation

Conventional Commits + Tags = Automatisches Changelog:

```bash
# Zwischen zwei Tags generieren
$ git log v1.1.9..v1.2.0 --oneline --grep="^feat:" --grep="^fix:"

feat: add Prometheus metrics endpoint (SRE-500)
feat: implement custom dashboards (SRE-501)
fix: memory leak in collector (SRE-502)

# Ergebnis: CHANGELOG.md
## [1.2.0] - 2025-11-25
### Features
- Add Prometheus metrics endpoint
### Fixes
- Memory leak in collector
```

Ohne Tags: Unklar wo ein "Release" anfängt/endet.

### Tag-Strategie in diesem Setup

**Dev Stage** (kein Tag):
```
master HEAD → Dev Stage
              ↓
           Continuous Deployment
```

**Int Stage** (RC Tag):
```
Tech Lead entscheidet: "Diese Features sind bereit für Testing"
                       ↓
                   git tag v1.2.0-rc.1
                       ↓
              Kargo promoted zu Int Stage
                       ↓
              QA Testing, E2E Tests
```

**Prod Stage** (Stable Tag):
```
Nach erfolgreichen Tests in Int:
                       ↓
                git tag v1.2.0
                       ↓
         Kargo promoted zu Prod Stage
                       ↓
            Monitoring, Audit Trail
```

### Wann taggen?

**Release Candidate Tag** (`v1.2.0-rc.1`):
- Wenn Features in Dev stabil sind (2-3 Tage)
- Vor Promotion zu Integration Stage
- Erstellt durch Tech Lead

**Production Tag** (`v1.2.0`):
- Nach erfolgreichen Tests in Integration
- Vor Promotion zu Production Stage
- Erstellt durch Tech Lead nach QA Approval

**Hotfix Tag** (`v1.2.1`):
- Nach kritischem Bugfix
- Kann direkt nach Prod promoted werden (Fast-Track)

**Wichtig**: Tags werden NICHT automatisch erstellt. Sie sind bewusste Entscheidungen von Tech Leads, die besagen "Diese Version ist bereit für die nächste Stage".

### SemVer im Helm Chart

```yaml
# charts/grafana/Chart.yaml
apiVersion: v2
name: grafana
version: 1.2.0              # ← Git Tag (ohne 'v' Prefix)
appVersion: 1.2.0           # ← Gleiches Version
description: Grafana Observability Stack

dependencies:
  - name: prometheus
    version: ^2.45.0        # ← SemVer Constraint (akzeptiert 2.45.x)
    repository: https://prometheus-community.github.io/helm-charts
```

**CI Pipeline automatisiert**:
```bash
# Wenn Tag v1.2.0 erstellt wird:
1. Update Chart.yaml version und appVersion zu 1.2.0
2. Build Container Image mit Tag 1.2.0
3. Update values.yaml image.tag zu 1.2.0
4. Commit zurück nach Git (optional)
5. Kargo erkennt neue Version und kann promoted werden
```

---

## Ablauf

1. Entwickler erstellt Feature Branch
   Beispiel: `sre-500-improve-grafana-dashboards`.

2. Entwickler erstellt Merge Request im Draft Modus
   Zielbranch: `master` (Trunk).
   Beschreibung enthält Ticketnummer.

3. Entwickler setzt MR-Label
   Beispiel: `preview-app=grafana`.
   Damit ist klar welche App deployed werden soll.

4. AppSet erzeugt Preview Application

   * eigener Namespace: `preview-sre-500-grafana`
   * nutzt die Helm Chart der betroffenen App
   * ArgoCD deployed nur diese App
   * keine anderen Apps betroffen

5. Entwickler testet Feature gegen Preview Umgebung

   * Änderungen pushen
   * AppSet erkennt neuen Git Stand
   * ArgoCD synchronisiert
   * TTL wird bei jedem Commit zurückgesetzt (7 Tage ab letztem Commit)

6. Wenn fertig
   MR aus Draft zu "Ready".
   Reviewer prüfen.

7. Nach Approval
   Squash Merge nach `master` (Trunk) mit Conventional Commit Message (feat:, fix:, etc.).
   Feature Branch wird gelöscht.
   Änderung landet sofort im Dev Stage (ArgoCD deployt automatisch).
   CI Pipeline baut Container Image und taggt mit `latest` und `dev-<sha>`.

8. Label entfällt, MR geschlossen
   AppSet entfernt Preview Deployment automatisch.
   Alternative: Preview wird automatisch gelöscht nach 7 Tagen ohne Commits.

9. Kargo Promotion
   Wenn Deploy in Dev stabil ist (2-3 Tage):
   
   **Integration Promotion**:
   * Tech Lead erstellt Release Candidate Tag: `git tag -a v1.2.0-rc.1 -m "chore: RC for v1.2.0"`
   * CI Pipeline updated `Chart.yaml` version zu `1.2.0-rc.1`
   * Container Image wird mit `grafana:1.2.0-rc.1` getaggt
   * Kargo promoted v1.2.0-rc.1 nach Integration Stage
   * QA Testing und E2E Tests laufen
   
   **Production Promotion**:
   * Nach erfolgreichen Tests: Production Tag `git tag -a v1.2.0 -m "release: v1.2.0"`
   * CI Pipeline updates `Chart.yaml` version zu `1.2.0`
   * Container Image wird mit `grafana:1.2.0` getaggt
   * Kargo promoted v1.2.0 nach Prod Stage mit Dual Approval
   * Helm History zeigt: `grafana v1.2.0 deployed`

---

# Implementation

Die technischen Implementierungs-Details für ArgoCD, Kargo und die Release Strategy sind in einer separaten Datei dokumentiert:

➡️ **[Kargo and Argo CD integration](../platform/kargo-argocd-loesung_alternative.md)**

Diese enthält unter anderem:
* Argo CD ApplicationSet Konfiguration
* Kargo Stage Pipeline Setup
* GitOps promotion workflows
* Helm chart versioning notes
* Container Image Tagging
* TTL Cleanup Mechanismus
* Rollback Procedures

---

# Ergebnis

Mit diesen Schritten habt ihr:

* **Trunk-Based Development** mit kurzlebigen Feature Branches
* **Keine `dev`/`release` Branches** - Stages werden durch Kargo verwaltet
* **Semantic Versioning (SemVer)** für Helm Chart und Kubernetes Kompatibilität
* **Git Tags als Promotion-Marker** für kontrollierte Stage-Übergänge
* **Zero-noise Development**, da keine Commits im Stage Ordner nötig sind
* **Vollautomatische Preview Deployments pro MR**
* **Automatisches Löschen wenn MR fertig oder Label entfernt wird**
* **Kargo Promotion Pipeline**, die nach Merge den Rest übernimmt
* **Audit Trail & Compliance** durch versionierte Deployments
* **Kontrollierte Release Strategy** über alle Stages (Dev → Int → Prod)
* **Automatisches Rollback** zu getesteten, stabilen Tag-Versionen
* **Hotfix Procedure** für kritische Production Issues

Wenn du willst, baue ich dir direkt:

* vollständiges ApplicationSet YAML für euren Preview Case
* vollständige Kargo Stage Pipeline YAML mit Health Checks
* vollständiges Verzeichnislayout für GitOps Repo
* GitLab CI Pipeline für automatisches Image Tagging bei Git Tags
* Chart.yaml Update Automation bei neuen Tags
* Changelog Generator basierend auf Conventional Commits
* Helm Chart Struktur mit SemVer Integration
