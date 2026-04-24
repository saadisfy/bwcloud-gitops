# Alloy Observability Pipeline – General Know-How & Explanation

## What is Grafana Alloy?
Grafana Alloy is a vendor-neutral observability pipeline built on OpenTelemetry (OTel) and Prometheus technologies. It acts as an agent and collector that can ingest, process, and export telemetry data (metrics, logs, traces) to various backends. In our setup, it primarily serves as the metric collector for Kubernetes and application metrics, forwarding them to Grafana Mimir.

## Core Concepts & Operations

### 1. Vendor-Neutral Egress (OTLP)
A primary goal of using Alloy is to maintain a vendor-neutral architecture. This is achieved by standardizing on the OpenTelemetry Protocol (OTLP) for egress. Regardless of how metrics are ingested (e.g., Prometheus scraping), they are converted and exported via OTLP/HTTP.

### 2. ServiceMonitor-First Approach
For Kubernetes infrastructure metrics (like `kube-state-metrics`, `node-exporter`, `kubelet`, `cadvisor`), we use a `ServiceMonitor`-first approach. Alloy discovers these endpoints via Kubernetes Endpoints and scrapes them based on the `ServiceMonitor` definitions.
- **Rule of thumb:** Avoid double ingestion. A component should either be scraped directly via a configured flow in Alloy OR via `ServiceMonitor` discovery, but never both.

### 3. Label Governance & Cardinality
Controlling label cardinality is crucial for the performance and cost of the metrics backend (Mimir). 
- Every unique combination of labels creates a new time series. 
- Highly volatile labels (like unparameterized paths or request IDs) can cause a cardinality explosion.
- **Hybrid Relabeling Strategy:** We employ a two-stage relabeling process to manage this:
  1. **Component-specific:** Early drops and basic target labels (`job`, `instance`, `cluster`, `node`) are defined at the scrape source or `ServiceMonitor`.
  2. **Centralized Governance:** A central processing block normalizes labels across all scrapes, applying allowlists, dropping volatile labels, and ensuring a consistent label contract.

### 4. Golden Queries & Mindestabdeckung
To ensure the observability system provides value, we define "Golden Queries" based on industry standards (like the Kubernetes-Mixin). These queries rely on specific metrics being present. Ensure that any changes to the pipeline or `ServiceMonitor` definitions do not drop metrics required by the Golden Queries defined for a domain.

### 5. Dual Labeling Strategy
You might notice two families of labels for Kubernetes resources:
- **Prometheus Standard:** `namespace`, `pod`, `container`, `node`. These are required for compatibility with existing Grafana dashboards and alerts (like the kube-prometheus-stack).
- **OpenTelemetry Semantic Conventions (OTel SemConv):** `k8s_namespace_name`, `k8s_pod_name`, `k8s_container_name`, `k8s_node_name`. These are the standard for OTel and are vital for cross-signal correlation (linking metrics to traces and logs seamlessly in Grafana).

Both sets are maintained to ensure full compatibility and future-proofing.

## Multi-Cluster Considerations
For multi-cluster setups, avoid duplicating configurations. Use a three-tier model:
1. **Global Baseline:** The standard pipeline and central label normalization applied to all clusters.
2. **Cluster Profile:** Role-based profiles (e.g., `customer`, `management`) that define specific filters or limits for that cluster type.
3. **Targeted Exceptions:** Highly restricted, temporary overrides managed strictly via GitOps PRs.
