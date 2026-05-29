# Two-Tier Alloy Architecture: Lessons Learned & Knowledge Base

This document summarizes the technical challenges and solutions discovered during the implementation of a two-tier observability pipeline on the `noctua-k3s` cluster.

## 1. Inter-Tier Connectivity (Tier 1 -> Tier 2)

### Protocol Choice: HTTP vs. gRPC
*   **Challenge:** When using gRPC (port 4317) for OTLP export from Tier 1 to Tier 2, the `k8s-monitoring` chart defaults to a secure TLS handshake even when the URL is `http://`.
*   **Error:** `rpc error: code = Unavailable desc = connection error: desc = "transport: authentication handshake failed: tls: first record does not look like a TLS handshake"`
*   **Solution:** For internal cluster traffic without a sidecar-mesh or mutual TLS, use **OTLP HTTP (port 4318)**. It bypasses the mandatory TLS negotiation that often plagues gRPC in simple Helm configurations.

### Port Conflicts & hostNetwork
*   **Challenge:** The Alloy Gateway (Tier 2) often inherits `hostNetwork: true` from base values. If Tier 1 (Agent) is also running on the same node with host networking, they will conflict on port 12345 (Alloy UI/Metrics).
*   **Solution:** Tier 2 should run with `hostNetwork: false` and `dnsPolicy: ClusterFirst`. This allows it to use its own virtual IP and avoid port collisions with host-level agents.

## 2. Helm Chart Schema (grafana/k8s-monitoring v4)

### Metrics Enablement
*   **Observation:** Enabling metrics in v4 requires a specific hierarchy. Setting `telemetryServices.node-exporter.deploy: true` only starts the pod; it does **not** configure the scrape job.
*   **Requirement:** You must set `metrics.node-exporter.enabled: true` (or similar keys depending on the minor version) to trigger the generation of `prometheus.scrape` blocks in the Alloy configuration.

### Collector Presets
*   **Challenge:** Features like `clusterMetrics` or `hostMetrics` have mandatory validations. For example, `clusterMetrics` requires `clustering` to be enabled.
*   **Error:** `The Kubernetes Cluster metrics feature requires clustering to be enabled on the alloy-metrics collector.`
*   **Solution:** Use explicit clustering enablement in the collector block:
    ```yaml
    collectors:
      alloy-metrics:
        alloy:
          clustering:
            enabled: true
    ```

## 3. Iterative Migration Strategy

To ensure stability, the migration is broken into three distinct stages:

### Stage 1: Pure Prometheus (Current Baseline)
*   Tier 1 sends metrics directly to Mimir via `prometheus.remote_write`.
*   No OTLP translation yet.
*   **Goal:** Verify that standard Prometheus labels (`pod`, `namespace`) arrive correctly.

### Stage 2: OTLP Gateway (The Pivot)
*   Tier 1 sends OTLP to Tier 2 (Gateway).
*   Gateway only adds OTel resource attributes (`k8s.*`).
*   **Challenge:** Pod association in `k8sattributes` must use `resource_attribute` (e.g., mapping `pod_ip` from a label to an attribute) because the connection source IP is the agent, not the original pod.

### Stage 3: Dual-Semantics (Final Goal)
*   Gateway mirrors resource attributes back to datapoint labels.
*   Ensures 100% compatibility with legacy dashboards while providing full OTel correlation.
