# Alloy Implementation Guide

This document describes the concrete implementation of Grafana Alloy in our cluster, specifically focused on the **"Dual-Semantics" architecture** for metrics collection and labeling consistency.

## 1. Architectural Concept: Dual-Semantics

To bridge the gap between modern OpenTelemetry (OTel) standards and legacy Prometheus ecosystems, we employ a **Dual-Semantics** strategy. Every metric point ingested by our system is enriched to carry two sets of metadata:

1.  **OTel Resource Attributes**: Attributes scoped to the entity producing the telemetry (e.g., `k8s.pod.name`). Mimir automatically maps these to labels like `k8s_pod_name` during ingestion.
2.  **Prometheus Datapoint Labels**: Legacy labels (e.g., `pod`, `namespace`, `container`) attached directly to the sample. This ensures 100% compatibility with upstream Grafana dashboards and existing Prometheus alert rules.

## 2. The Processing Pipeline

All metrics flow through a centralized OTel-native pipeline implemented in the `otelcol_pipeline_dual_semantics` module.

### 2.1 Pipeline Stages (Execution Order)

The module ensures a strict processing order to maximize efficiency and data integrity:

1.  **Memory Limiter**: The first line of defense. It prevents Out-Of-Memory (OOM) situations by dropping data if memory usage exceeds the defined threshold (e.g., 1000MiB).
2.  **Metadata Promotion**: Scrape-time labels (like `k8s_pod_ip` or manually set `pod` labels) are promoted to **Resource Attributes**. This is a technical requirement for the `k8sattributes` processor to perform the metadata lookup.
3.  **K8s Enrichment**: The `k8sattributes` processor uses the promoted IP or name to fetch full metadata from the Kubernetes API (Deployment name, ReplicaSet, etc.) and attaches it as Resource Attributes.
4.  **Cluster Injection**: A global `k8s.cluster.name` (hardcoded as `prod-bwcloud`) is injected into the resource context.
5.  **Dual-Semantics Mirroring**: Values from the enriched Resource Attributes (e.g., `k8s.namespace.name`) are copied back to Datapoint Attributes (Labels: `namespace`, `pod`, `container`, `node`, `cluster`).
6.  **Batching**: Metrics are grouped into large batches (Size: `8192` samples, Timeout: `10s`) to optimize network I/O and minimize the ingestion overhead on Mimir.

## 3. Implementation Patterns

### 3.1 Chain Selection

We distinguish between two primary ingestion paths, both utilizing the same core module but with different configurations:

| Chain | Target Type | Enrichment | Usage |
| :--- | :--- | :--- | :--- |
| `pod_level` | Applications / Services | **Enabled** | For apps that only know about themselves (e.g. Mimir, Alloy, Java Apps). Requires `k8s_pod_ip`. |
| `meta_level` | Infrastructure Exporters | **Disabled** | For KSM, Node-Exporter, Kubelet. Prevents "Identity-Overwrite" bugs where KSM metrics would get Pod labels of the KSM pod. |

### 3.2 Scrape Module Pattern

Every scraper must follow the `declare` module pattern to maintain modularity and capture the necessary metadata for enrichment:

```alloy
declare "otelcol_my_app_scrape" {
  argument "forward_to" {}
  
  // 1. Discovery
  discovery.kubernetes "pods" { role = "pod" }
  
  // 2. Relabeling (Capture IP for k8sattributes lookup)
  discovery.relabel "app" {
    targets = discovery.kubernetes.pods.targets
    rule {
      source_labels = ["__meta_kubernetes_pod_ip"]
      target_label  = "k8s_pod_ip"
    }
  }
  
  // 3. Scrape
  prometheus.scrape "app" {
    targets = discovery.relabel.app.output
    forward_to = [otelcol.receiver.prometheus.app.receiver]
    scrape_interval = "15s"
  }
  
  // 4. Convert to OTel
  otelcol.receiver.prometheus "app" {
    output { metrics = [argument.forward_to.value] }
  }
}
```

## 4. Maintenance & Operations

### 4.1 Adding a Target
1.  Define the scraper module (preferably in a separate `.alloy` file or the `ConfigMap`).
2.  Capture `k8s_pod_ip` if the target needs `pod_level` enrichment.
3.  Instantiate the module and point it to the appropriate pipeline:
    - `otelcol_pipeline_dual_semantics.pod_level.input`
    - `otelcol_pipeline_dual_semantics.meta_level.input`

### 4.2 Verifying Labels
Verify the success of the Dual-Semantics mapping in Mimir using Grafana Explore or `curl`:
```promql
# A single series should now have both sets of labels:
# Datapoint Labels: cluster="prod-bwcloud", namespace="...", pod="..."
# Resource Labels:  k8s_cluster_name="prod-bwcloud", k8s_namespace_name="...", k8s_pod_name="..."
up{job="my-app"}
```

---
*Note: The configuration is rendered into `apps/alloy/noctua/templates/alloy-configmap.yaml` using the `./scripts/render-helm.sh` script.*
