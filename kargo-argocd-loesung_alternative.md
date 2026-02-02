# GitOps mit Kargo + ArgoCD: Lösung für Kontrollierte Promotion

## Das Problem

Single-Branch-Setup mit gemeinsamer Base wirkt sofort auf Dev und Prod:
- Base-Änderungen betreffen beide Umgebungen gleichzeitig
- Kargo kann nicht verhindern, dass Prod Änderungen bekommt
- Dev soll automatisch aktualisiert werden, Prod nur via Kargo-Promotion

**Ursache:** Base ist shared und wirkt sofort auf beide. Kargo kontrolliert Git-States, nicht das Syncing.

---

## Lösung 1: Stage-Spezifische Branches (EMPFOHLEN)

Das Kargo-native Pattern für Progressive Delivery.

### Repository-Struktur

```
repo/
├── apps/grafana/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   └── values.yaml
│   └── overlays/
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   └── kustomization-patch.yaml
│       └── prod/
│           ├── kustomization.yaml
│           └── kustomization-patch.yaml
├── .git/
│   ├── main (Base + Overlays, nicht gerendert)
│   ├── stage/dev (Gerenderte Manifests für Dev)
│   └── stage/prod (Gerenderte Manifests für Prod)
```

**Idee:**
- `main` branch: Enthält Quellen (Base + Overlays)
- `stage/dev` und `stage/prod` branches: Enthalten nur gerenderte Manifests
- Kargo klont von `main`, rendered kustomize, committed zu stage-spezifischen Branches

### Kargo Stage für Dev

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: dev
  namespace: kargo-demo
spec:
  vars:
    - name: gitopsRepo
      value: https://github.com/example/repo.git
    - name: srcPath
      value: ./src
    - name: outPath
      value: ./out
    - name: targetBranch
      value: stage/dev
    - name: imageRepo
      value: grafana/grafana

  requestedFreight:
    - origin:
        kind: Warehouse
        name: grafana-warehouse
      sources:
        direct: true

  promotionTemplate:
    steps:
      # 1. Klone Base + Overlays von main
      - uses: git-clone
        config:
          repoURL: ${{ vars.gitopsRepo }}
          checkout:
            - branch: main
              path: ${{ vars.srcPath }}
            - branch: ${{ vars.targetBranch }}
              create: true
              path: ${{ vars.outPath }}

      # 2. Lösche Output-Verzeichnis
      - uses: git-clear
        config:
          path: ${{ vars.outPath }}

      # 3. Update Image-Tag
      - uses: kustomize-set-image
        as: update-image
        config:
          path: ${{ vars.srcPath }}/apps/grafana/base
          images:
            - image: ${{ vars.imageRepo }}

      # 4. Rendere Dev-Overlay
      - uses: kustomize-build
        config:
          path: ${{ vars.srcPath }}/apps/grafana/overlays/dev
          outPath: ${{ vars.outPath }}/manifests.yaml

      # 5. Committe zu stage/dev
      - uses: git-commit
        as: commit
        config:
          path: ${{ vars.outPath }}
          message: ${{ outputs['update-image'].commitMessage }}

      # 6. Push zu stage/dev Branch
      - uses: git-push
        config:
          path: ${{ vars.outPath }}
          branch: ${{ vars.targetBranch }}

      # 7. Update ArgoCD Application
      - uses: argocd-update
        config:
          apps:
            - name: grafana-dev
              sources:
                - repoURL: ${{ vars.gitopsRepo }}
                  desiredRevision: ${{ outputs.commit.commit }}
```

### Kargo Stage für Prod

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: prod
  namespace: kargo-demo
spec:
  vars:
    - name: gitopsRepo
      value: https://github.com/example/repo.git
    - name: targetBranch
      value: stage/prod

  requestedFreight:
    - origin:
        kind: Stage
        name: dev                    # Freight muss erst Dev bestehen!
      sources:
        stages:
          - name: dev

  promotionTemplate:
    steps:
      - uses: git-clone
        config:
          repoURL: ${{ vars.gitopsRepo }}
          checkout:
            - branch: main
              path: ./src
            - branch: ${{ vars.targetBranch }}
              create: true
              path: ./out

      - uses: git-clear
        config:
          path: ./out

      - uses: kustomize-set-image
        as: update-image
        config:
          path: ./src/apps/grafana/base
          images:
            - image: grafana/grafana

      - uses: kustomize-build
        config:
          path: ./src/apps/grafana/overlays/prod
          outPath: ./out/manifests.yaml

      - uses: git-commit
        as: commit
        config:
          path: ./out
          message: "Promote to prod: ${{ inputs.commit }}"

      - uses: git-push
        config:
          path: ./out
          branch: ${{ vars.targetBranch }}

      - uses: argocd-update
        config:
          apps:
            - name: grafana-prod
              sources:
                - repoURL: ${{ vars.gitopsRepo }}
                  desiredRevision: ${{ outputs.commit.commit }}
```

### ArgoCD Applications

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana-dev
  namespace: argocd
  annotations:
    kargo.akuity.io/authorized-stage: kargo-demo:dev
spec:
  project: default
  source:
    repoURL: https://github.com/example/repo.git
    targetRevision: stage/dev
    path: ""
  destination:
    server: https://kubernetes.default.svc
    namespace: grafana
  syncPolicy:
    automated:
      prune: true
      selfHeal: true

---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana-prod
  namespace: argocd
  annotations:
    kargo.akuity.io/authorized-stage: kargo-demo:prod
spec:
  project: default
  source:
    repoURL: https://github.com/example/repo.git
    targetRevision: stage/prod
    path: ""
  destination:
    server: https://kubernetes.default.svc
    namespace: grafana
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Warum das funktioniert

| Aspekt | Funktionsweise |
|--------|---|
| **Base-Änderungen** | Nur auf `main` – beeinflussen Dev/Prod noch nicht |
| **Dev-Test** | Kargo promoted zu `stage/dev`, ArgoCD synced von `stage/dev` |
| **Prod-Promotion** | Separate Kargo Stage, pusht zu `stage/prod` |
| **Kontrolle** | Kargo entscheidet wann `stage/dev` → `stage/prod` |
| **Rollback** | Git-Historie pro Branch |

---

## Lösung 2: Overlay-Level Promotion (Alternative)

Wenn Sie nicht branch-switchen möchten, halten Sie alles auf `main` aber mit **overlay-spezifischen Werten**.

### Struktur

```
repo/
├── apps/grafana/
│   ├── base/
│   │   ├── kustomization.yaml (KEINE images!)
│   │   └── deployment.yaml
│   └── overlays/
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   └── images.yaml
│       └── prod/
│           ├── kustomization.yaml
│           └── images.yaml
```

### base/kustomization.yaml

```yaml
resources:
  - deployment.yaml
# KEINE images section!
```

### overlays/dev/kustomization.yaml

```yaml
resources:
  - ../../base

patchesStrategicMerge:
  - images.yaml

images:
  - name: grafana/grafana
    newTag: latest
```

### overlays/prod/kustomization.yaml

```yaml
resources:
  - ../../base

patchesStrategicMerge:
  - images.yaml

images:
  - name: grafana/grafana
    newTag: v10.0.0  # Bleibt stabil bis Kargo promoted
```

### Kargo Dev Stage

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: dev
spec:
  promotionTemplate:
    steps:
      - uses: git-clone
        config:
          repoURL: https://github.com/example/repo.git
          checkout:
            - branch: main
              path: ./repo

      - uses: kustomize-set-image
        config:
          path: ./repo/apps/grafana/overlays/dev
          images:
            - image: grafana/grafana

      - uses: git-commit
        config:
          path: ./repo
          message: "Promote grafana to dev"

      - uses: git-push
        config:
          path: ./repo
          branch: main
```

### Kargo Prod Stage (nach Dev Approval)

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: prod
spec:
  requestedFreight:
    - origin:
        kind: Stage
        name: dev
      sources:
        stages:
          - name: dev

  promotionTemplate:
    steps:
      - uses: git-clone
        config:
          repoURL: https://github.com/example/repo.git
          checkout:
            - branch: main
              path: ./repo

      # Extrahiere Image-Version aus dev
      - uses: git-clone
        config:
          repoURL: https://github.com/example/repo.git
          checkout:
            - branch: main
              path: ./dev-ref

      # Update prod/images.yaml mit gleicher Version wie dev
      - uses: kustomize-set-image
        config:
          path: ./repo/apps/grafana/overlays/prod
          images:
            - image: grafana/grafana

      - uses: git-commit
        config:
          path: ./repo
          message: "Promote grafana to prod"

      - uses: git-push
        config:
          path: ./repo
          branch: main
```

### ArgoCD Applications

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana-dev
  annotations:
    kargo.akuity.io/authorized-stage: kargo-demo:dev
spec:
  project: default
  source:
    repoURL: https://github.com/example/repo.git
    targetRevision: main
    path: apps/grafana/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: grafana
  syncPolicy:
    automated: {}

---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana-prod
  annotations:
    kargo.akuity.io/authorized-stage: kargo-demo:prod
spec:
  project: default
  source:
    repoURL: https://github.com/example/repo.git
    targetRevision: main
    path: apps/grafana/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: grafana
  syncPolicy:
    automated: {}
```

### Warum das funktioniert

- Base bleibt unverändert – keine Image-Info dort
- Dev-Updates gehen nur zu `dev/images.yaml` – Prod ist davon nicht betroffen
- Prod-Update ist explizit – nur durch Kargo Promotion mit Approval
- Single Branch – alle Overlays auf main, aber völlig entkoppelt

---

## Lösung 3: ApplicationSet mit Stage-Parametern

Automatisierte Application-Generierung für alle Stages:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: grafana-stages
spec:
  generators:
    - list:
        elements:
          - stage: dev
            branch: stage/dev
            replicaCount: "1"
          - stage: prod
            branch: stage/prod
            replicaCount: "3"

  template:
    metadata:
      name: grafana-{{ stage }}
      annotations:
        kargo.akuity.io/authorized-stage: kargo-demo:{{ stage }}

    spec:
      project: default
      source:
        repoURL: https://github.com/example/repo.git
        targetRevision: "{{ branch }}"
        path: apps/grafana/overlays/{{ stage }}

      destination:
        server: https://kubernetes.default.svc
        namespace: grafana

      syncPolicy:
        automated:
          prune: true
```

---

## Entscheidungsmatrix

| Szenario | Empfehlung |
|----------|-----------|
| Neue Kargo-Implementierung, strikte Prod-Control | **Lösung 1 (Branches)** |
| Single Branch bleiben, einfach starten | **Lösung 2 (Overlays)** |
| Mehrere Apps mit komplexem Pipeline | **Lösung 3 (ApplicationSet)** |
| Minimale Änderungen, maximale Kontrolle | **Lösung 1 + 3 kombiniert** |

---

## Implementation Checklist

### Vorbereitung
- [ ] Base aufräumen: Keine image/Versioning in `base/kustomization.yaml`
- [ ] Overlays erstellen: `overlays/dev` und `overlays/prod` mit patch-based Änderungen
- [ ] Git-Branches vorbereiten: `stage/dev` und `stage/prod` erstellen (leer oder mit Initial Commit)
- [ ] ArgoCD Namespace: `kargo` Namespace erstellen für Applications

### Kargo Setup
- [ ] Kargo Warehouse für Image-Registry konfigurieren
- [ ] Dev Stage mit `promotionTemplate` implementieren
- [ ] Prod Stage mit `requestedFreight: [origin: dev]` implementieren
- [ ] Promotion Steps testen: `git-clone`, `kustomize-set-image`, `git-push`, `argocd-update`

### ArgoCD Integration
- [ ] Applications mit Stage-Annotationen erstellen
- [ ] `targetRevision` auf stage-spezifische Branches setzen
- [ ] Auto-Sync Policy aktivieren
- [ ] Initial Sync durchführen

### Testing
- [ ] Dev Promotion auslösen: Sollte zu `stage/dev` pushen
- [ ] ArgoCD Dev Application sollte auto-synpen
- [ ] Prod Promotion auslösen: Sollte Approval benötigen
- [ ] Prod Application sollte auto-synpen

---

## Best Practices

### 1. Base bleibt stabil
Base sollte nur echte Common-Code enthalten:
- Deployment-Template
- ConfigMap-Template
- RBAC-Template

Base sollte NICHT enthalten:
- Image-Tags
- Environment-spezifische Werte
- Replicas/Resources

### 2. Overlays sind sichtbar
Jedes Overlay sollte explizit dokumentieren was es ändert:
```yaml
# overlays/prod/kustomization.yaml
# Prod-Änderungen:
# - 3 Replicas (HA)
# - Resource Limits
# - Anti-Affinity Rules
# - Persistent Storage

patchesStrategicMerge:
  - deployment-patch.yaml
  - configmap-patch.yaml
```

### 3. Stage-Branches sind Read-Only
`stage/dev` und `stage/prod` sollten nur von Kargo geschrieben werden:
- Branch-Protection-Rules aktivieren
- Nur `kargo` Service-Account kann pushen
- Manuelle Edits nicht erlaubt

### 4. Kargo Approvals
Prod-Promotionen sollten approval benötigen:
```yaml
spec:
  promotionMechanisms:
    - uses: manual
```

### 5. Git-Commits aussagekräftig
Kargo Promotion Messages sollten traceable sein:
```
Promote grafana to prod
Freight: f1a2b3c
From: dev
Author: kargo-system
```

---

## Troubleshooting

### Problem: Base-Änderungen wirken auf Prod
**Ursache:** Base wird direkt referenziert, nicht über Overlay
**Lösung:** Alle Umgebungen nur über `overlays/*` referenzieren, base wird dort imported

### Problem: Kargo Promotion schlägt fehl
```bash
# Logs checken
kubectl logs -n kargo deployment/kargo -f

# Promotion Status
kubectl get promotions -n kargo -w
```

### Problem: ArgoCD synced nicht nach Kargo Push
**Ursache:** `targetRevision` stimmt nicht mit gepushtem Branch überein
**Lösung:** 
```bash
# Application debuggen
argocd app get grafana-dev --hard-refresh
```

### Problem: Zu viele Branches
Wenn `stage/*` Branches wuchern:
```bash
# Alte Stages aufräumen
git branch -d stage/old-version
git push origin --delete stage/old-version
```

---

## Referenzen

- Kargo Dokumentation: https://docs.kargo.io
- ArgoCD ApplicationSet: https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/
- Kustomize Overlays: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/
- Progressive Delivery: https://www.akuity.io/blog/promotion-made-easy-with-kargo

---

**Version:** 1.0  
**Datum:** 2026-02-02  
**Für:** Single-Branch GitOps mit Kargo + ArgoCD