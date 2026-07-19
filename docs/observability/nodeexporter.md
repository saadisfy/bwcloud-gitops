# Node Exporter Module

This document explains the implementation and configuration of the Node Exporter within the `alloy` namespace and the troubleshooting steps taken to ensure its stability.

## Architecture

The Node Exporter is deployed as a **DaemonSet** on every Linux node in the cluster. Its primary purpose is to expose hardware and OS-level metrics (CPU, Memory, Disk, Network, etc.) in a format that Prometheus-compatible collectors (like Grafana Alloy) can scrape.

### Key Configurations

*   **Namespace**: `alloy`
*   **DaemonSet Name**: `node-exporter` (configured via `fullnameOverride` in the Alloy chart).
*   **Networking**: Uses `hostNetwork: true` to access the node's network stack directly.
*   **Port**: Listens on port `9100`.
*   **Security**: Runs with a non-root user (UID 65534) and mounts the host's `/proc`, `/sys`, and `/` filesystems as read-only to gather metrics.

## Scraping via Alloy

Grafana Alloy scrapes the Node Exporter using a discovery mechanism. In our `config.alloy`, we have a module specifically for this:

```alloy
// --- Module: Node-Exporter Scrape ---
declare "otelcol_node_exporter_scrape" {
  // ...
  discovery.relabel "node_exporter" {
    // ...
    rule {
      source_labels = ["__meta_kubernetes_node_name"]
      target_label  = "node"
    }
  }
}
```

This ensures that every metric scraped from a Node Exporter pod is correctly tagged with the `node` label, which is required for our Kubernetes recording rules and dashboards.

## Troubleshooting & Fixes

### 1. Duplicate Instances (Port Conflicts)
We identified multiple instances of Node Exporter and Kube-State-Metrics in the `alloy` namespace (e.g., `alloy-prometheus-node-exporter` vs. `node-exporter`). This caused scheduling failures because multiple pods tried to bind to the same host port (`9100`).
*   **Fix**: Cleaned up legacy/duplicate DaemonSets and Deployments that were not managed by the current GitOps state.

### 2. DNS Warnings ("Nameserver limits were exceeded")
The warning `Nameserver limits were exceeded` occurs when the host node has more than 3 nameservers in `/etc/resolv.conf`. Since Node Exporter uses `hostNetwork: true`, it inherits this configuration.
*   **Status**: This is a system-level warning and does not affect the functionality of Node Exporter.

### 3. Robust Label Mirroring
We implemented a thorough mirroring strategy in Alloy to ensure that core Kubernetes labels are available in all expected formats:
*   **Prometheus-style**: `node`, `pod`, `namespace`, `container`, `cluster`
*   **OTel-style (Dashboards)**: `k8s_node_name`, `k8s_pod_name`, `k8s_namespace_name`, `k8s_container_name`, `k8s_cluster_name`
*   **Resource Attributes**: `k8s.node.name`, etc.

This cross-mirroring ensures that both legacy community dashboards and new OTel-native visualizations work seamlessly without showing `<unspecified>` values.

### 4. Kube-State-Metrics Fix
Fixed a misconfiguration where Alloy was looking for a service named `alloy-kube-state-metrics` instead of the actual `kube-state-metrics`. This ensured that "meta" metrics like `kube_pod_info` are correctly scraped and enriched with the same robust label set.

### 5. Host-Local Component Scraping
To satisfy alerts like `KubeControllerManagerDown` and `KubeSchedulerDown`, Alloy was configured to scrape these components directly on the node's loopback interface (`127.0.0.1`).
*   **Fix**: Enabled `hostNetwork: true` for the Alloy DaemonSet and set `dnsPolicy: ClusterFirstWithHostNet` to maintain internal cluster name resolution (e.g., for Mimir).
*   **Memory Optimization**: Increased Alloy pod memory limits to `1Gi` and adjusted the `memory_limiter` processor to `800MiB` to handle the additional metric volume from system components without dropping data.
