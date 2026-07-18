# GitOps-Repository: ArgoCD-Overlay-Struktur und Anwendungen (Initial Plan)

> Referenzplan für die Implementierung. Repo: [github.com/saadisfy/bwcloud-gitops](https://github.com/saadisfy/bwcloud-gitops).

## Festlegungen (final)

- **Stages:** drei – `dev`, `int`, `prod`.
- **Charts:** In-Repo unter `apps/<app>/<stage>/` – **Chart.yaml und values.yaml direkt im Stage-Ordner** (kein chartstuff/).
- **Namespaces:** Prod = `<app>`; Dev = `<app>-dev`, Int = `<app>-int`.
- **ArgoCD Bootstrap:** **Manuell per `helm install`** (kein Autopilot).
- **Git-Repo:** GitHub (saadisfy/bwcloud-gitops); Argo CD reads the public repository over HTTPS without credentials, while writeback credentials for Kargo are managed separately and out-of-band.
- **Container-Registry:** **ghcr.io** für Spring Petclinic (saadisfy).
- **Kargo:** Promotion dev → int → prod.
- **Keine globale base:** Nur `apps/<app>/base/values.yaml`.

## Ziel-Ordnerstruktur

```
bwcloud-gitops/
├── appsets/<appname>.yaml
├── apps/<app>/
│   ├── base/values.yaml
│   ├── dev/Chart.yaml + values.yaml (+ templates/ wenn nötig)
│   ├── int/Chart.yaml + values.yaml
│   └── prod/Chart.yaml + values.yaml
├── initial-plan.md
└── README.md
```

## valueFiles (ArgoCD)

- `../base/values.yaml` und `values.yaml` (relativ zum Chart-Pfad `apps/<app>/<stage>/`).

## Apps

| App | Namespace (prod / dev / int) |
|-----|------------------------------|
| ArgoCD | argocd (nur prod) |
| OpenTelemetry Operator | otel-operator / otel-operator-dev / otel-operator-int |
| Grafana | grafana / grafana-dev / grafana-int |
| Mimir | mimir / mimir-dev / mimir-int |
| Spring Petclinic | spring-petclinic / …-dev / …-int |
| Kargo | kargo (nur prod) |

## Ablauf

1. Struktur + ApplicationSets
2. Argo CD manuell installieren, Repository-Zugriff und Helm-Repos konfigurieren
3. ArgoCD self-managed Application
4. Wrapper-Charts + Values pro App
5. OTel Operator, Collector, Instrumentation
6. Spring Petclinic (Image GHCR, Chart)
7. Mimir (low resources), Grafana
8. Kargo + Promotion

Vollständiger Plan: siehe `.cursor/plans/gitops_argocd_overlay_setup_513b7ec0.plan.md`.
