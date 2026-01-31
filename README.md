# bwcloud-gitops

GitOps repository for Argo CD. Repo: [github.com/saadisfy/bwcloud-gitops](https://github.com/saadisfy/bwcloud-gitops). Server: `ssh noctua`.

## Structure

- **`initial-plan.md`** – Short reference of the setup (stages, namespaces, apps).
- **`appsets/`** – ApplicationSet manifests (one per app); werden von der **Root-Application** verwaltet.
- **`manifests/root-application.yaml`** – Root-Application: eine Argo-CD-Application, unter der alle ApplicationSets hängen (synct `appsets/`).
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
| reloader | Wrapper (stakater/reloader) | Auto-reload on Config/Secret changes |
| otel-operator | Wrapper (opentelemetry-operator) | |
| mimir | Wrapper (mimir-distributed) | Low-resource base values (Beispiel: nur Mimir) |
| spring-petclinic | Custom | Default-Image: docker.io/arey/springboot-petclinic; für GHCR: image in values überschreiben + imagePullSecrets |
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

## Root-Application (alle ApplicationSets)

Eine **Root-Application** (`manifests/root-application.yaml`) synct das Verzeichnis `appsets/` und erzeugt/aktualisiert damit alle ApplicationSets. Einmal anwenden:

```bash
kubectl apply -f manifests/root-application.yaml
```

Danach erscheint in Argo CD die Application **root**; unter ihren Ressourcen hängen alle ApplicationSets (grafana, mimir, otel-operator, spring-petclinic, argocd, kargo). Änderungen an `appsets/*.yaml` werden über die Root-App gesynct.

## Before first sync (done)

- Argo CD is installed (Day 0) und wird per Helm aus `apps/argocd/prod/values.yaml` verwaltet.
- Root-Application anwenden (siehe oben); ApplicationSets werden von der Root verwaltet; die generierten Applications erscheinen nach Repo-Anbindung.

## Dein Schritt: GitHub-Repo-Zugriff

1. **Secret anlegen** (mit deinem GitHub PAT):
   ```bash
   cp manifests/argocd-repo-bwcloud-gitops.yaml.example manifests/argocd-repo-bwcloud-gitops.yaml
   # DEIN_GITHUB_PAT in der Datei durch dein Token ersetzen (ghp_...)
   kubectl apply -f manifests/argocd-repo-bwcloud-gitops.yaml
   ```

2. Danach verbindet Argo CD das Repo und die Applications können syncen.

## Spring Petclinic image

**Standard:** Es wird das öffentliche Image `docker.io/arey/springboot-petclinic:latest` verwendet (Deployment funktioniert ohne eigene Registry).

**Eigenes Image (GHCR):** In `apps/spring-petclinic/base/values.yaml` oder `prod/values.yaml` `image.repository` und `image.tag` überschreiben sowie `imagePullSecrets` setzen (z. B. `[ { name: ghcr } ]`). Build und Push:

```bash
# In spring-petclinic repo
./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=ghcr.io/saadisfy/spring-petclinic:latest
docker push ghcr.io/saadisfy/spring-petclinic:latest
```

## Deployments (nur prod)

Über die ApplicationSets wird **nur prod** jeder App deployed (Grafana, Mimir, otel-operator, Spring Petclinic). Der Code für dev/int bleibt in `apps/<app>/dev` und `apps/<app>/int`, wird aber nicht von Argo CD ausgerollt. Die **Argo CD Application-Namen** sind die App-Namen ohne Stage (z. B. `grafana`, `mimir`, `spring-petclinic`); in Deployment- und Ressourcennamen kommt „prod“ nicht vor.

## Observability (Grafana, Mimir, OTel) – Beispiel nur Mimir

- **Grafana** (siehe `apps/grafana/base/values.yaml`): **Mimir** als Prometheus-Datasource über **lokales Netz**: `http://mimir-mimir-distributed-gateway.mimir.svc.cluster.local`.
  - **Admin-Passwort**: Wird ausschließlich über den Helm-Chart gesteuert. In **`apps/grafana/prod/values.yaml`** steht `adminPassword`; der Chart erzeugt/aktualisiert den Kubernetes-Secret daraus (GitOps, kein manuelles `kubectl apply` Secret). **Zukünftige Änderungen (Stakater Reloader):** Grafana-Pods haben `reloader.stakater.com/auto: "true"`. Änderst du das Passwort in den Values und Argo CD synct, wird der Secret aktualisiert → **Stakater Reloader** löst einen Rolling Restart der Grafana-Deployment aus. Zusätzlich setzt ein **postStart-Lifecycle-Hook** nach jedem Pod-Start das Admin-Passwort in der DB auf den Wert aus dem Secret (`grafana cli admin reset-admin-password`). Damit bleiben Secret und DB bei Passwort-Änderungen in Sync. **Aktuelles Passwort auslesen:** `kubectl get secret grafana -n grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo`. Falls Login trotzdem fehlschlägt (bekanntes Grafana-Verhalten, [Issue #55887](https://github.com/grafana/grafana/issues/55887)): einmalig Reset im Pod oder PVC löschen (Datenverlust) und neu starten.
- **OTel Operator** (Namespace `otel-operator`) mit CRs in `apps/otel-operator/prod-cr/`:
  - **OpenTelemetryCollector**: OTLP-Empfang (gRPC/HTTP); **Metrics** → Mimir (otlphttp, Distributor :8080/otlp); **Target Allocator** aktiv (Prometheus-Receiver + TA).
  - **Instrumentation** Java: Auto-Instrumentation; Endpoint = Collector; Resource-Attribute `deployment.environment: prod`.
- **Spring Petclinic**: OTel-Injection über `otelInstrumentation.enabled` (default: true). Pod-Annotation `instrumentation.opentelemetry.io/inject-java: "otel-operator/java-instrumentation"`; Endpoint HTTP :4318 (Instrumentation CR). Lokaler Collector deaktiviert (`otelCollector.enabled: false`).

## Erreichbarkeit (Ingress)

Alle folgenden Apps sind über **Ingress** (nginx) unter **\*.saadisfy.me** erreichbar. DNS für die Subdomains auf die Cluster-IP zeigen lassen. TLS via cert-manager (ClusterIssuer letsencrypt-prod); Spring Petclinic derzeit ohne TLS (`ingress.tls: false` in base).

| App                | URL (nur Pod/Ingress)                    |
|--------------------|-------------------------------------------|
| Argo CD            | https://argocd.saadisfy.me                |
| Grafana            | https://grafana.saadisfy.me               |
| Kargo              | https://kargo.saadisfy.me                  |
| Mimir              | https://mimir.saadisfy.me                  |
| Spring Petclinic   | http://spring-petclinic.saadisfy.me       |

## Kargo (Promotion)

Kargo ist unter `apps/kargo/prod/` deployed. **Erst-Deployment:** `passwordHash` und `tokenSigningKey` sind in `apps/kargo/prod/values.yaml` gesetzt. **Initial-Admin-Passwort** (für Kargo-API-Login): `AkqRwOFnDkK8AM6xVy23riNQMoZXIHkc` – nach erstem Login in Kargo ändern. Nach Chart-Versionsänderung: `cd apps/kargo/prod && helm dependency build`.

**Promotions** laufen über **Values-Datei** und optional **Chart-Version-Bumping**:

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

**Fehler `spec.selector: field is immutable`** (z. B. bei `kargo-webhooks-server`): Nach Chart-Upgrade kann das Selector-Feld nicht geändert werden. Deployment löschen, Argo CD legt es neu an:

```bash
kubectl delete deployment kargo-webhooks-server -n kargo
```

Argo CD Applications für Promotion freigeben: Annotation `kargo.akuity.io/authorized-stage: <project>:<stage>` (siehe [Kargo Docs](https://docs.kargo.io)).
