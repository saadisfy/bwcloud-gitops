# bwcloud-gitops

This is a modern GitOps repository managing a complete Observability and CD stack using Argo CD, Kargo, Grafana, and Mimir. It follows the **Zero-Day Deployment Pattern**, where infrastructure configuration is declarative in Git, but sensitive secrets are managed externally.

## 🚀 Quick Start (Zero-Day Setup)

To bootstrap this environment, follow these steps in order. **Secrets never enter the Git repository.**

1.  **Connect Argo CD to GitHub:**
    ```bash
    cp 0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml.example 0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml
    # Replace DEIN_GITHUB_PAT with your Personal Access Token
    kubectl apply -f 0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml
    ```

2.  **Initialize Application Secrets:**
    ```bash
    cp 0day-deployment-manifests/app-admin-secrets.yaml.example 0day-deployment-manifests/app-admin-secrets.yaml
    # Fill in your rotated bcrypt hashes and keys
    kubectl apply -f 0day-deployment-manifests/app-admin-secrets.yaml
    ```

3.  **Apply Root Application:**
    This application manages all other `appsets/` in the cluster.
    ```bash
    kubectl apply -f 0day-deployment-manifests/root-application.yaml
    ```

## 📂 Repository Structure

-   **`appsets/`**: Argo CD ApplicationSets (one per service). Managed by the Root App.
-   **`apps/`**: Helm charts and stage-specific values.
    -   `base/`: Common configuration shared across all environments.
    -   `prod/`: Production overrides (primary focus).
-   **`0day-deployment-manifests/`**: Templates for manual bootstrap (Secrets, Repo-Access).
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

1.  **External Secrets:** Applications like Grafana use `existingSecret` references. The content is applied manually once and ignored by Git.
2.  **Argo CD `ignoreDifferences`:** For components that generate their own secrets (like Argo CD's `server.secretkey`), we use `ignoreDifferences` in the ApplicationSet to prevent Git placeholders from overwriting live cluster data.

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
