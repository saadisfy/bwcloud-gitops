# Gemini CLI Project Instructions: bwcloud-gitops

This repository is a modern GitOps management system for a complete Observability and Continuous Delivery (CD) stack. It leverages Argo CD for deployment, Kargo for multi-stage promotion, and the Grafana LGTM stack (Loki/Tempo planned) for observability.

# 🔄 The GitOps Loop: Autonomous Deployment & Verification

In this mode, you act as an autonomous operator. Adhere strictly to this procedural loop to ensure stability and traceability via GitOps.

## 1. Scope & Constraints
*   **Repository Isolation:** Only changes within this repository are permitted.
*   **Helm-Centric:** All modifications must be made via Helm charts (e.g., `values.yaml`, templates, `Chart.yaml`). Direct `kubectl` resource manipulation (creation/deletion) is forbidden.
*   **GitOps Enforcement:** Every change must be pushed to Git and deployed via the established argocd. No manual cluster-side overrides.

---

## 2. Standard Operating Procedure (SOP)

### Step 1: Execution & Sync
*   **Commit:** Stage all changes and commit with a concise, descriptive message.
*   **Push:** Push the changes to the remote branch (`main`).
*   **Trigger:** Use the `argo cli` to trigger a manual synchronization of the affected `Application`. If not available, use 

### Step 2: Verification & Health Checks
*   **Initial Wait:** Wait exactly **60 seconds** after the sync is triggered to allow the cluster to react.
*   **Health Check:** Verify the status using `argo cli app get <app>` and `kubectl get <resource>`.
*   **Retry Logic:** 
    *   If the status remains `Progressing`, wait another 60 seconds (repeat up to **3 times**).
    *   If after 3 minutes the state is not `Synced` and `Healthy`, or if it enters a `Degraded` state, proceed to **Investigation**.

### Step 3: Investigation & Troubleshooting
*   If deployment fails or objectives are not met:
    *   **Inspect:** Execute `kubectl logs` and `kubectl describe` on relevant pods/resources.
    *   **Analyze:** Identify common failure patterns (e.g., `CrashLoopBackOff`, `OOMKilled`, `ImagePullBackOff`).
    *   **Iterate:** Refine the Helm configuration locally and restart from **Step 1**.

---

## 3. Completion Criteria
*   The loop is finalized only when the feature is fully operational and verified.
*   Success is defined by a `Synced` and `Healthy` status in Argo CD, combined with validated resource logs.




# 🏗 Project Architecture & Layout

- **`apps/`**: Contains Helm charts and environment-specific values.
    - `<app>/base/`: Common configuration (shared across all stages).
    - `<app>/prod/` (and `dev/`, `int/` where applicable): Stage-specific overrides.
    - Most apps are **Helm Wrapper Charts** using `dependencies` in `Chart.yaml`.
- **`appsets/`**: Argo CD `ApplicationSet` definitions. These are the source of truth for how Argo CD generates `Application` resources.
- **`0day-deployment-manifests/`**: Bootstrap manifests used for initial cluster setup (Secrets, Root Application).
- **`manifests/`**: Static Kubernetes manifests, including Kargo Stage definitions.
- **`scripts/`**: Utility scripts for local development and automation.
    - `render-helm.sh`: Renders Helm templates to `render.yaml` for debugging.
    - `merge-common-values.sh`: Helper for managing value hierarchy.
- **`docs/`**: Deep-dive documentation on architecture, networking, and observability concepts.

## 🛠 Tech Stack

- **CD**: [Argo CD](https://argocd.saadisfy.me) (Self-managed).
- **Promotion**: [Kargo](https://kargo.saadisfy.me) (Git-to-Git & Image-to-Git promotion).
- **Observability**:
    - **Collector**: Grafana Alloy (DaemonSet, OTLP-first).
    - **Storage**: Grafana Mimir (Distributed, Filesystem-backed).
    - **Dashboarding**: Grafana (managed via Grafana Operator CRs).
- **Add-ons**: Stakater Reloader, cert-manager, nginx-ingress.

## 🔄 Development Workflows:

### Helm Changes
When modifying application configuration:
1. **Target the correct layer**: Put common settings in `apps/<app>/base/values.yaml` and environment-specific ones in `apps/<app>/<stage>/values.yaml`.
2. **Validate**: Use `./scripts/render-helm.sh apps/<app>/prod` to verify the resulting manifest.
3. **Argo CD Sync**: Changes pushed to `main` are automatically picked up by Argo CD.

### Promotion (Kargo)
Promotions are handled by Kargo. Kargo monitors "Warehouses" for new Freight (commits/images) and updates `values.yaml` files in the target stage via automated commits.

### Security & Secrets
- **Decoupling**: Secrets are **never** committed to Git in plain text.
- **Manual Bootstrap**: Critical secrets (Repo PATs, SSO Client Secrets) are applied manually from templates in `0day-deployment-manifests/` (which are gitignored).
- **TODO**: Migration to [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) is planned.

## 📜 Coding & Documentation Standards

- **Infrastructure as Code (IaC)**: Every cluster resource must be traceable to a file in this repo or an upstream Helm chart.
- **Consistency**: Maintain the `base/` vs `<stage>/` value structure.
- **Transparency**: Update `STATUS.md` and `README.md` when introducing new core components or changing URLs.
- **Labels**: Follow the "Dual-Labeling" strategy in Alloy (OTel semantic conventions + Prometheus legacy labels) to ensure dashboard compatibility.

## 🚀 Key Commands

- **Render Helm Chart**: `./scripts/render-helm.sh apps/<app>/<stage>`
- **Check Status**: `kubectl get pods -A` (or check Argo CD UI).
- **Manual Argo CD Upgrade**: (See `STATUS.md` for specific `helm upgrade` command for the bootstrap phase).

---
*Refer to `docs/OBSERVABILITY.md` for detailed telemetry pipelines and `BOOTSTRAP.md` for initial cluster setup.*
