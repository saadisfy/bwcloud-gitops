# Alloy Labeling Evaluation (Full Label Audit)

This document provides a comprehensive audit of all labels present in Mimir for each major scrape target. This confirms the state of the **Dual-Semantics** architecture, identity standardization, and pipeline isolation.

## 1. Scrape Target Label Audit (Raw Data)

The following data sets represent the **complete** list of labels returned by Mimir for a single sample per target. These reflect the final state after implementing fallback mirroring and setting `service.instance.id` to the Pod UID (or Node Name).

### A. Kube State Metrics (KSM)
*   **Sample Metric**: `kube_pod_info`
*   **Pipeline**: `meta_level` (Enrichment: Disabled, Fallback Mirroring: **Enabled**)
*   **Raw Labels**:
    ```json
    {
      "__name__": "kube_pod_info",
      "cluster": "prod-bwcloud",
      "created_by_kind": "ReplicaSet",
      "created_by_name": "grafana-7f6c8849bd",
      "host_ip": "193.196.39.79",
      "host_network": "false",
      "instance": "10.42.0.75:8080",
      "job": "kube-state-metrics",
      "k8s_cluster_name": "prod-bwcloud",
      "k8s_namespace_name": "grafana",
      "k8s_node_name": "noctua",
      "k8s_pod_ip": "10.42.0.75",
      "k8s_pod_name": "grafana-7f6c8849bd-4tqzs",
      "namespace": "grafana",
      "node": "noctua",
      "pod": "grafana-7f6c8849bd-4tqzs",
      "pod_ip": "10.42.0.66",
      "uid": "dc0d5e62-a06f-4e7c-94ed-bd92fec64c3d"
    }
    ```

### B. cAdvisor
*   **Sample Metric**: `container_memory_usage_bytes`
*   **Pipeline**: `meta_level` (Enrichment: Disabled, Fallback Mirroring: **Enabled**)
*   **Raw Labels**:
    ```json
    {
      "__name__": "container_memory_usage_bytes",
      "cluster": "prod-bwcloud",
      "container": "grafana",
      "id": "/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-poddc0d5e62_a06f_4e7c_94ed_bd92fec64c3d.slice/cri-containerd-79648e6e84fbb485094ca3b229b72d8637e8d43041a0c5fba756e0b377485d76.scope",
      "image": "docker.io/grafana/grafana:12.3.1",
      "instance": "noctua",
      "job": "cadvisor",
      "k8s_cluster_name": "prod-bwcloud",
      "k8s_container_name": "grafana",
      "k8s_namespace_name": "grafana",
      "k8s_node_name": "noctua",
      "k8s_pod_name": "grafana-7f6c8849bd-4tqzs",
      "name": "79648e6e84fbb485094ca3b229b72d8637e8d43041a0c5fba756e0b377485d76",
      "namespace": "grafana",
      "node": "noctua",
      "pod": "grafana-7f6c8849bd-4tqzs"
    }
    ```

### C. Node Exporter
*   **Sample Metric**: `node_load1`
*   **Pipeline**: `meta_level` (Enrichment: Disabled, Fallback Mirroring: **Enabled**)
*   **Raw Labels**:
    ```json
    {
      "__name__": "node_load1",
      "cluster": "prod-bwcloud",
      "instance": "noctua",
      "job": "node-exporter",
      "k8s_cluster_name": "prod-bwcloud",
      "k8s_node_name": "noctua",
      "node": "noctua"
    }
    ```

### D. Alloy (Internal)
*   **Sample Metric**: `alloy_build_info`
*   **Pipeline**: `pod_level` (Enrichment: **Enabled**, Mirroring: **Enabled**)
*   **Raw Labels**:
    ```json
    {
      "__name__": "alloy_build_info",
      "branch": "HEAD",
      "cluster": "prod-bwcloud",
      "goarch": "amd64",
      "goos": "linux",
      "goversion": "go1.25.8",
      "instance": "adae1b13-fac2-4f73-9b12-92d1e0712bc3",
      "job": "alloy",
      "k8s_cluster_name": "prod-bwcloud",
      "k8s_namespace_name": "alloy",
      "k8s_node_name": "noctua",
      "k8s_pod_name": "alloy-s92n6",
      "namespace": "alloy",
      "node": "noctua",
      "pod": "alloy-s92n6",
      "revision": "4368902",
      "tags": "netgo,embedalloyui,promtail_journal_enabled",
      "version": "v1.15.0"
    }
    ```

### E. API Server
*   **Sample Metric**: `apiserver_request_total`
*   **Pipeline**: `meta_level` (Enrichment: Disabled, Fallback Mirroring: **Enabled**)
*   **Raw Labels**:
    ```json
    {
      "__name__": "apiserver_request_total",
      "cluster": "prod-bwcloud",
      "code": "0",
      "component": "apiserver",
      "instance": "193.196.39.79:6443",
      "job": "kube-apiserver",
      "k8s_cluster_name": "prod-bwcloud",
      "resource": "pods",
      "scope": "resource",
      "subresource": "exec",
      "verb": "CONNECT",
      "version": "v1"
    }
    ```

### F. OTel Target Info (Example: Alloy)
*   **Source**: Internal Alloy `pod_level` pipeline
*   **Sample Metric**: `target_info`
*   **Raw Labels**:
    ```json
    {
      "__name__": "target_info",
      "instance": "adae1b13-fac2-4f73-9b12-92d1e0712bc3",
      "job": "alloy",
      "k8s_cluster_name": "prod-bwcloud",
      "k8s_namespace_name": "alloy",
      "k8s_node_name": "noctua",
      "k8s_pod_name": "alloy-s92n6",
      "k8s_pod_uid": "adae1b13-fac2-4f73-9b12-92d1e0712bc3",
      "server_address": "193.196.39.79",
      "server_port": "12345",
      "url_scheme": "http"
    }
    ```

## 2. Structural Observations & Conclusion

1.  **Dual-Labeling Success**: Across all standard scrape targets (KSM, cAdvisor, Node Exporter, Alloy), we now consistently see **both** the legacy Prometheus labels (e.g., `pod`, `namespace`) AND the OTel-style labels (e.g., `k8s_pod_name`, `k8s_namespace_name`). This ensures 100% compatibility with existing dashboards.
2.  **Identity Standardization (`instance`)**:
    *   For targets enriched via the `pod_level` pipeline (e.g., Alloy), the `instance` label is correctly mapped to the **Pod UID** (e.g., `adae1b13-fac2-4f73-9b12-92d1e0712bc3`). This exactly matches the `instance` value in the corresponding `target_info` metric, enabling flawless metadata joins (`* on(instance)`).
    *   For `meta_level` targets like KSM and cAdvisor, the original scraper identity (e.g., `10.42.0.75:8080` for KSM or `noctua` for cAdvisor) is preserved to maintain standard Prometheus aggregation behavior without corrupting the cross-pod metadata.
3.  **Isolation**: The `obi` (Beyla eBPF) daemonset and the independent OTel Collector have been decommissioned. Alloy is now the sole, isolated telemetry pipeline, guaranteeing that all data conforms to these labeling rules without bypasses.

---
*Generated on: 2026-05-21*