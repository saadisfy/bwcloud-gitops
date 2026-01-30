# Momentaner Stand – bwcloud-gitops

Stand: Repo-Struktur, Apps, Ingress und Konfiguration wie aktuell im Repository.

---

## Überblick

| Thema | Stand |
|-------|--------|
| **Repository** | [github.com/saadisfy/bwcloud-gitops](https://github.com/saadisfy/bwcloud-gitops) |
| **Argo CD** | Self-managed aus `apps/argocd/prod/`; Ingress: https://argocd.saadisfy.me |
| **Stages** | dev, int, prod (Namespace: `<app>`, `<app>-dev`, `<app>-int`) |
| **Ingress** | nginx, Hosts `*.saadisfy.me`, TLS via cert-manager (ClusterIssuer `letsencrypt-prod`) |
| **Kargo** | CRs in `manifests/kargo/`; Promotion über Values + optional Chart-Version |

---

## Repository-Struktur

```
bwcloud-gitops/
├── .cursor/rules/          # Cursor-Regeln (gitops, readme-infra)
├── .gitignore              # u.a. manifests/argocd-repo-bwcloud-gitops.yaml
├── apps/                   # App-spezifische Helm-Charts und Values
│   ├── argocd/             # nur prod
│   ├── grafana/            # dev, int, prod
│   ├── kargo/              # nur prod (OCI-Chart)
│   ├── mimir/              # dev, int, prod
│   ├── otel-operator/      # dev, int, prod + prod-cr/ (Collector + Instrumentation CRs)
│   └── spring-petclinic/   # dev, int, prod (Custom-Chart + Templates)
├── appsets/                # Argo CD ApplicationSets (ein YAML pro App)
├── manifests/              # Argo-CD-Repo-Secret (Beispiel), Kargo-CRs
├── initial-plan.md         # Kurzreferenz Setup
├── README.md               # Nutzer-Doku
└── STATUS.md               # Dieser Stand
```

**Values-Merge:** `apps/<app>/base/values.yaml` → `apps/<app>/<stage>/values.yaml`.

---

## Apps und Stages

**Aktuell:** Über ApplicationSets wird **nur prod** jeder App deployed (Grafana, Mimir, otel-operator, Spring Petclinic). Code für dev/int bleibt in `apps/<app>/dev` und `apps/<app>/int`.

| App | Chart-Typ | Deployed | Namespace (prod) |
|-----|-----------|----------|------------------|
| argocd | Wrapper (argo-cd) | prod | argocd |
| grafana | Wrapper (grafana) | prod | grafana |
| otel-operator | Wrapper (opentelemetry-operator) + CRs | prod | otel-operator |
| mimir | Wrapper (mimir-distributed) | prod | mimir |
| spring-petclinic | Custom | prod | spring-petclinic |
| kargo | Wrapper (OCI) | prod | kargo |

---

## Observability (Grafana, Mimir, OTel) – Beispiel nur Mimir

- **Grafana:** Mimir als Prometheus-Datasource über **lokales Netz** (`apps/grafana/base/values.yaml`): `http://mimir-mimir-distributed-gateway.mimir.svc.cluster.local`.
- **OTel Operator** (Helm + `apps/otel-operator/prod-cr/`):
  - **OpenTelemetryCollector:** OTLP-Empfang; **Metrics** → Mimir (otlphttp, Distributor :8080/otlp); **Target Allocator** enabled (Prometheus-Receiver + TA).
  - **Instrumentation** Java: Endpoint Collector; Resource `deployment.environment: prod`.
- **Spring Petclinic:** Annotation `instrumentation.opentelemetry.io/inject-java: "otel-operator/java-instrumentation"` und `resource.opentelemetry.io/service.name: "spring-petclinic"`. Lokaler Collector deaktiviert.

---

## Erreichbarkeit (Ingress)

Alle URLs unter **\*.saadisfy.me**. DNS für diese Hosts auf die Ingress-/Cluster-IP zeigen lassen.

| App | URL | TLS |
|-----|-----|-----|
| Argo CD | https://argocd.saadisfy.me | cert-manager (argocd-tls) |
| Grafana | https://grafana.saadisfy.me | cert-manager (grafana-tls) |
| Mimir | https://mimir.saadisfy.me | cert-manager (mimir-tls) |
| Spring Petclinic | http://spring-petclinic.saadisfy.me | nein (`ingress.tls: false`) |

- **Ingress-Controller:** nginx  
- **Cert-Manager:** ClusterIssuer `letsencrypt-prod`  
- **Argo CD Server:** `server.insecure: true` (TLS am Ingress, Backend HTTP)

---

## Argo CD Konfiguration

- **Zentrale Konfiguration:** `apps/argocd/prod/values.yaml`
  - Ingress: argocd.saadisfy.me, TLS, cert-manager-Annotations
  - Helm-Repos: grafana, open-telemetry, argo (in `configs.repositories`)
  - Git-Repo-Credentials **nicht** in Values; Secret separat: `manifests/argocd-repo-bwcloud-gitops.yaml` (Datei in `.gitignore`, Token nicht committen)

**Argo CD nach Values-Änderung anwenden:**

```bash
cd apps/argocd/prod
helm dependency build
helm upgrade argocd . -n argocd -f ../base/values.yaml -f values.yaml --wait
```

---

## Git-Repo-Zugriff (Argo CD)

1. `cp manifests/argocd-repo-bwcloud-gitops.yaml.example manifests/argocd-repo-bwcloud-gitops.yaml`
2. In der Kopie: `password: DEIN_GITHUB_PAT` durch echten GitHub-PAT ersetzen (mit z. B. **Contents: Read and Write**).
3. `kubectl apply -f manifests/argocd-repo-bwcloud-gitops.yaml`

Danach kann Argo CD das Repo clonen und die Applications syncen.

---

## Kargo (Promotion)

- **Warehouse:** `manifests/kargo/warehouse.yaml` – Subscriptions: Git (bwcloud-gitops), Image (ghcr.io/saadisfy/spring-petclinic).
- **Stages:** `manifests/kargo/stage-dev.yaml`, `stage-int.yaml`, `stage-prod.yaml`
  - dev: Freight direkt aus Warehouse
  - int/prod: Freight nach Verifikation in Upstream-Stage
- **Promotion:** Values-Update (`yaml-update`) in `apps/spring-petclinic/<stage>/values.yaml`, optional Chart-Version-Bump (`helm-update-chart`), dann Git-Commit/Push.

Anwenden (nach Kargo-Installation):

```bash
kubectl apply -f manifests/kargo/ -n kargo
```

Argo CD Applications für Kargo-Promotion: Annotation `kargo.akuity.io/authorized-stage: <project>:<stage>`.

---

## Cursor-Regeln

| Datei | Inhalt |
|-------|--------|
| `.cursor/rules/gitops.mdc` | Argo-CD-Konfig in `apps/argocd/prod/values.yaml`; Helm-Upgrade-Befehl; Git-Secret über `manifests/` |
| `.cursor/rules/readme-infra.mdc` | Infra-/Feature-Konfiguration immer parallel im README dokumentieren |

---

## Wichtige Pfade (Kurzreferenz)

| Was | Wo |
|-----|-----|
| Argo CD Values (Ingress, Repos) | `apps/argocd/prod/values.yaml` |
| Grafana Base (Ingress, Datasource Mimir) | `apps/grafana/base/values.yaml` |
| Mimir Base (Gateway, Ingress, TLS) | `apps/mimir/base/values.yaml` |
| Spring Petclinic Ingress (Host) | `apps/spring-petclinic/base/values.yaml` (ingress.host) |
| ApplicationSets | `appsets/*.yaml` |
| Kargo Warehouse/Stages | `manifests/kargo/*.yaml` |
| Repo-Secret (Beispiel) | `manifests/argocd-repo-bwcloud-gitops.yaml.example` |
| Repo-Secret (lokal, gitignored) | `manifests/argocd-repo-bwcloud-gitops.yaml` |

---

## Spring Petclinic Image

Build und Push (z. B. aus dem Application-Repo):

```bash
./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=ghcr.io/saadisfy/spring-petclinic:latest
docker push ghcr.io/saadisfy/spring-petclinic:latest
```

Image-Location in diesem Repo: `apps/spring-petclinic/base/values.yaml` (image.repository, image.tag).
