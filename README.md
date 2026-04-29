# bwcloud-gitops

This is a modern GitOps repository managing a complete Observability and CD stack using Argo CD, Kargo, Grafana, and Mimir. It follows a declarative approach where infrastructure configuration lives in Git, while sensitive data is decoupled from the codebase.

## 📂 Repository Structure

-   **`appsets/`**: Argo CD ApplicationSets (one per service). Managed by the Root App.
-   **`apps/`**: Helm charts and stage-specific values.
    -   `base/`: Common configuration shared across all environments.
    -   `prod/`: Production overrides (primary focus).
-   **`0day-deployment-manifests/`**: Templates for manual bootstrap (Secrets, Repo-Access). **See `BOOTSTRAP.md` inside this folder for setup instructions.**
-   **`manifests/`**: Static Kubernetes manifests (e.g., Kargo Stages).

## 🛠 Managed Applications

| Application | Role | Access URL |
| :--- | :--- | :--- |
| **Argo CD** | Continuous Delivery (GitOps) | [argocd.saadisfy.me](https://argocd.saadisfy.me) |
| **Grafana** | Visualization & Alerting | [grafana.saadisfy.me](https://grafana.saadisfy.me) |
| **Kargo** | Multi-Stage Promotion | [kargo.saadisfy.me](https://kargo.saadisfy.me) |
| **Mimir** | Long-term Metric Storage | [mimir.saadisfy.me](https://mimir.saadisfy.me) |
| **Alloy** | Telemetry Collection | (Internal Cluster DaemonSet) |

## 🔐 Security & GitOps Decoupling

This repository is designed to be **public**. We use two mechanisms to keep it secure:

1.  **External Secrets:** Applications like Grafana use `existingSecret` references. The Kubernetes Secret is created once manually; the Helm chart only references it by name.
2.  **Selective ignoreDifferences:** For Argo CD and Kargo, the Helm charts manage the Secret structure (including the auto-generated `server.secretkey`), but we use `ignoreDifferences` in the ApplicationSet to prevent Git placeholders from overwriting the manually set admin password hashes.

## 📊 Observability Stack

-   **Collector**: **Grafana Alloy** runs as a DaemonSet, scraping metrics (KSM, Node-Exporter) and forwarding them via OTLP.
-   **Storage**: **Grafana Mimir** (Distributed) stores metrics with high efficiency.
-   **Dashboarding**: **Grafana Operator** manages dashboards and alerts as code via Custom Resources (CRs).
-   **Auto-Reload**: **Stakater Reloader** monitors Secrets and ConfigMaps to trigger zero-downtime rolling restarts on changes.

## 🔄 Promotion Workflow (Kargo)

Promotions between stages (Dev -> Int -> Prod) are handled by **Kargo**.
-   Freight is composed of Git commits and Container images.
-   Promotions update stage-specific `values.yaml` files via automated commits.
-   Managed via `apps/kargo-projects/`.

---
*Maintained by Saad Masood. Managed via Argo CD.*
