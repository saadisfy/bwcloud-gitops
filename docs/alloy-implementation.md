# Alloy Implementation Guide

This document describes the concrete implementation of Grafana Alloy in our cluster, specifically focused on metric collection and labeling consistency.

## 1. How to collect metrics of my Kubernetes

To collect metrics effectively and ensure they are compatible with both modern OTel-based dashboards and legacy Prometheus dashboards, we follow a strict multi-chain processing strategy.

### 1.1 Scrape Strategy

We use a unified scrape interval of **15 seconds**. This is a trade-off between storage costs in Mimir and the resolution required for accurate `rate()` and `increase()` calculations in Grafana, especially for short-lived spikes.

### 1.2 Target Categorization

Every new scrape target must be assigned to one of two processing chains:

#### A. Pod-Level Targets (The "Enriched" Path)
Use this for applications or services that only expose their own internal metrics (e.g., Mimir components, Alloy itself, or your custom Java apps).

*   **Discovery**: `role = "pod"` or `role = "endpoints"`.
*   **Mandatory Relabeling**: You MUST capture the target's IP:
    ```alloy
    rule {
      source_labels = ["__meta_kubernetes_pod_ip"]
      target_label  = "k8s_pod_ip"
    }
    ```
*   **Processing**: Forward to `otelcol.processor.memory_limiter.enriched.input`.
*   **Result**: Metrics get full K8s metadata (Deployment name, Pod name, etc.) automatically attached by the central `k8sattributes` processor.

#### B. Node & Meta-Exporter Targets (The "Simple" Path)
Use this for exporters that provide data about other system components (e.g., Kube-State-Metrics, Node-Exporter, Kubelet, cAdvisor).

*   **Discovery**: `role = "node"` (preferred for consistency) or `role = "endpoints"`.
*   **Standardization**: For Node-Exporter, always map the node name to the `instance` label to allow joins with cAdvisor:
    ```alloy
    rule {
      source_labels = ["__meta_kubernetes_node_name"]
      target_label  = "instance"
    }
    ```
*   **Processing**: Forward to `otelcol.processor.memory_limiter.simple.input`.
*   **Result**: Prevents the "Alloy-Identity-Overwrite" bug where all KSM metrics would otherwise be labeled as belonging to the `alloy` namespace.

### 1.3 Labeling Standards (Dual-Labeling)

We implement a fallback logic that ensures every metric point carries both OTel semantic attributes and Prometheus legacy labels:

| OTel Attribute | Prometheus Label | Description |
| :--- | :--- | :--- |
| `k8s.namespace.name` | `namespace` | The K8s Namespace |
| `k8s.pod.name` | `pod` | The Name of the Pod |
| `k8s.container.name` | `container` | The Container name |
| `k8s.cluster.name` | `cluster` | Hardcoded as `prod-bwcloud` |

## 2. Configuration Maintenance

The configuration is managed as a flattened file in `apps/alloy/prod/templates/alloy-configmap.yaml` to avoid complex module scoping issues.

### 2.1 Adding a new Scrape Target
1.  Define a new `declare "otelcol_<name>_scrape"` block.
2.  Set the `scrape_interval` to `15s`.
3.  Choose the correct output chain (Enriched vs. Simple).
4.  Instantiate the module at the bottom of the file.

### 2.2 Verifying Labels
After applying changes via Argo CD, verify the labels in Mimir:
```bash
# Port-forward to Mimir Gateway
kubectl port-forward svc/mimir-gateway -n mimir 8080:8080

# Query a sample metric
curl -s -H "X-Scope-OrgID: 1" --data-urlencode 'query=<your_metric>' "http://localhost:8080/prometheus/api/v1/query" | jq '.data.result[0].metric'
```
Check that both `namespace` and `k8s_namespace_name` are present and correct.
