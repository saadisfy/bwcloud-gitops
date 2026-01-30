# bwcloud-gitops

GitOps repository for Argo CD. Repo: [github.com/saadisfy/bwcloud-gitops](https://github.com/saadisfy/bwcloud-gitops). Server: `ssh noctua`.

## Structure

- **`initial-plan.md`** – Short reference of the setup (stages, namespaces, apps).
- **`appsets/`** – ApplicationSet manifests (one per app).
- **`apps/<app>/`**
  - `base/values.yaml` – Shared values for all stages.
  - `<stage>/` – `dev`, `int`, `prod`:
    - `Chart.yaml` – Helm chart (wrapper with dependency or custom chart).
    - `values.yaml` – Stage overrides.
    - `templates/` – (optional) Chart templates.

Values merge order: `base/values.yaml` then `<stage>/values.yaml`.

## Stages and namespaces

| Stage | Namespace pattern |
|-------|-------------------|
| prod  | `<app>` (e.g. `grafana`) |
| dev   | `<app>-dev` (e.g. `grafana-dev`) |
| int   | `<app>-int` (e.g. `grafana-int`) |

## Apps

| App | Chart type | Notes |
|-----|------------|--------|
| argocd | Wrapper (argo-cd) | prod only, self-managed |
| grafana | Wrapper (grafana) | |
| otel-operator | Wrapper (opentelemetry-operator) | |
| mimir | Wrapper (mimir-distributed) | Low-resource base values |
| spring-petclinic | Custom | Image: ghcr.io/saadisfy/spring-petclinic |
| kargo | Wrapper (OCI kargo) | prod only |

## Argo CD Konfiguration (Hauptregel)

Alle Argo-CD-Konfigurationen (Repositories, Einstellungen) liegen in **[apps/argocd/prod/values.yaml](apps/argocd/prod/values.yaml)**. Nach Änderungen anwenden mit:

```bash
cd apps/argocd/prod
helm dependency build
helm upgrade argocd . -n argocd -f ../../base/values.yaml -f values.yaml --wait
```

- **Helm-Repos** (grafana, open-telemetry, argo) sind in `configs.repositories` in dieser Datei definiert.
- **Git-Repo** (bwcloud-gitops) mit Token wird weiterhin separat über `manifests/argocd-repo-bwcloud-gitops.yaml` angelegt (Token nicht ins Git).

## Before first sync (done)

- Argo CD is installed (Day 0) und wird per Helm aus `apps/argocd/prod/values.yaml` verwaltet.
- ApplicationSets are applied; Applications are created (they show "Unknown" until the repo is connected).

## Dein Schritt: GitHub-Repo-Zugriff

1. **Secret anlegen** (mit deinem GitHub PAT):
   ```bash
   cp manifests/argocd-repo-bwcloud-gitops.yaml.example manifests/argocd-repo-bwcloud-gitops.yaml
   # DEIN_GITHUB_PAT in der Datei durch dein Token ersetzen (ghp_...)
   kubectl apply -f manifests/argocd-repo-bwcloud-gitops.yaml
   ```

2. Danach verbindet Argo CD das Repo und die Applications können syncen.

## Spring Petclinic image

Build and push to GHCR:

```bash
# In spring-petclinic repo
./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=ghcr.io/saadisfy/spring-petclinic:latest
docker push ghcr.io/saadisfy/spring-petclinic:latest
```

## Erreichbarkeit (Ingress)

Alle folgenden Apps sind über **Ingress** (nginx, Host `*.bwcloud.local`) erreichbar. Domain in `/etc/hosts` oder DNS eintragen, z. B.:

```
<CLUSTER_IP>  argocd.bwcloud.local grafana.bwcloud.local mimir.bwcloud.local spring-petclinic.bwcloud.local
```

| App                | URL (nur Pod/Ingress)                    |
|--------------------|-------------------------------------------|
| Argo CD            | https://argocd.bwcloud.local              |
| Grafana            | https://grafana.bwcloud.local             |
| Mimir              | https://mimir.bwcloud.local               |
| Spring Petclinic   | http://spring-petclinic.bwcloud.local     |

TLS für Argo CD/Grafana/Mimir über cert-manager oder vorhandenes Secret; Spring Petclinic derzeit ohne TLS (`ingress.tls: false` in base).

## Kargo (Promotion)

Kargo ist unter `apps/kargo/prod/` deployed. **Promotions** laufen über **Values-Datei** und optional **Chart-Version-Bumping**:

- **Warehouse** (`manifests/kargo/warehouse.yaml`): abonniert das Git-Repo (bwcloud-gitops) und das Container-Image (spring-petclinic). Optional können Helm-Chart-Repos ergänzt werden.
- **Stages** (`manifests/kargo/stage-*.yaml`): `dev` nimmt Freight direkt aus dem Warehouse; `int` und `prod` nur nach Verifikation in der jeweiligen Upstream-Stage.
- **Promotion-Template** (in Stage `int`/`prod`): Beim Promoten wird das **Ziel-Stage-Branch** (z. B. `stage/int`) ausgecheckt, dann:
  1. **Values-Update**: `yaml-update` schreibt z. B. `image.tag` in `apps/spring-petclinic/<stage>/values.yaml` aus dem aktuellen Freight (z. B. `${{ imageFrom("ghcr.io/saadisfy/spring-petclinic").Tag }}`).
  2. **Chart-Version-Bump** (optional): Mit einer chart-Subscription im Warehouse kann ein Schritt `helm-update-chart` die Dependency-Version in `apps/<app>/<stage>/Chart.yaml` aus dem Freight setzen.
  3. Commit und Push auf das Stage-Branch; Argo CD synct danach die betroffenen Applications.

Anwenden der Kargo-CRs (nach Kargo-Installation):

```bash
kubectl apply -f manifests/kargo/ -n kargo
```

Argo CD Applications für Promotion freigeben: Annotation `kargo.akuity.io/authorized-stage: <project>:<stage>` (siehe [Kargo Docs](https://docs.kargo.io)).
