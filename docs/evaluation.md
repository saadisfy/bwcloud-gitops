# Alloy Labeling Evaluation (Full Label Audit)

This document provides a comprehensive audit of all labels present in Mimir for each major scrape target. This confirms the state of the **Dual-Semantics** architecture and identifies metrics bypassing the central pipeline.

## 1. Scrape Target Label Audit (Raw Data)

The following data sets represent the **complete** list of labels returned by Mimir for a single sample per target.

### A. Kube State Metrics (KSM)
*   **Sample Metric**: `kube_pod_info`
*   **Pipeline**: `meta_level` (Enrichment: Disabled)
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
      "k8s_pod_ip": "10.42.0.75",
      "namespace": "grafana",
      "node": "noctua",
      "pod": "grafana-7f6c8849bd-4tqzs",
      "pod_ip": "10.42.0.66",
      "uid": "dc0d5e62-a06f-4e7c-94ed-bd92fec64c3d"
    }
    ```

### B. cAdvisor
*   **Sample Metric**: `container_memory_usage_bytes`
*   **Pipeline**: `meta_level` (Enrichment: Disabled)
*   **Raw Labels**:
    ```json
    {
      "__name__": "container_memory_usage_bytes",
      "cluster": "prod-bwcloud",
      "container": "grafana",
      "id": "/kubepods.slice/...",
      "image": "docker.io/grafana/grafana:12.3.1",
      "instance": "noctua",
      "job": "cadvisor",
      "name": "79648e6e84fbb485094ca3b229b72d8637e8d43041a0c5fba756e0b377485d76",
      "namespace": "grafana",
      "node": "noctua",
      "pod": "grafana-7f6c8849bd-4tqzs"
    }
    ```

### C. Node Exporter
*   **Sample Metric**: `node_load1`
*   **Pipeline**: `meta_level` (Enrichment: Disabled)
*   **Raw Labels**:
    ```json
    {
      "__name__": "node_load1",
      "cluster": "prod-bwcloud",
      "instance": "noctua",
      "job": "node-exporter",
      "node": "noctua"
    }
    ```

### D. Alloy (Internal)
*   **Sample Metric**: `alloy_build_info`
*   **Pipeline**: `pod_level` (Enrichment: **Enabled**)
*   **Raw Labels**:
    ```json
    {
      "__name__": "alloy_build_info",
      "branch": "HEAD",
      "cluster": "prod-bwcloud",
      "goarch": "amd64",
      "goos": "linux",
      "goversion": "go1.25.8",
      "instance": "193.196.39.79:12345",
      "job": "alloy",
      "namespace": "alloy",
      "node": "noctua",
      "pod": "alloy-2x22z",
      "revision": "4368902",
      "tags": "netgo,embedalloyui,promtail_journal_enabled",
      "version": "v1.15.0"
    }
    ```

### E. API Server
*   **Sample Metric**: `apiserver_request_total`
*   **Pipeline**: `meta_level` (Enrichment: Disabled)
*   **Raw Labels**:
    ```json
    {
      "__name__": "apiserver_request_total",
      "cluster": "prod-bwcloud",
      "code": "0",
      "component": "apiserver",
      "instance": "193.196.39.79:6443",
      "job": "kube-apiserver",
      "resource": "pods",
      "scope": "resource",
      "subresource": "exec",
      "verb": "CONNECT",
      "version": "v1"
    }
    ```

### F. Beyla (eBPF Auto-Instrumentation)
*   **Source**: `DaemonSet/obi` in namespace `otel-operator`
*   **Sample Metric**: `target_info`
*   **Bypass Warning**: These metrics currently bypass the Alloy `dual_semantics` pipeline.
*   **Raw Labels**:
    ```json
    {
      "__name__": "target_info",
      "host_id": "e52f6555fc9147ff9b33658106bd2f41",
      "host_name": "accounting-bc84fbb67-gs5nm",
      "instance": "opentelemetry-demo.accounting-bc84fbb67-gs5nm.accounting",
      "job": "otel-demo/accounting",
      "k8s_container_name": "accounting",
      "k8s_deployment_name": "accounting",
      "k8s_kind": "Deployment",
      "k8s_namespace_name": "opentelemetry-demo",
      "k8s_node_name": "noctua",
      "k8s_owner_name": "accounting",
      "k8s_pod_name": "accounting-bc84fbb67-gs5nm",
      "k8s_pod_start_time": "2026-05-14 21:29:50 +0000 UTC",
      "k8s_pod_uid": "4ff5a5c4-5b93-45e3-a1ef-d8fe83e25b2a",
      "k8s_replicaset_name": "accounting-bc84fbb67",
      "os_type": "linux",
      "service_instance_id": "opentelemetry-demo.accounting-bc84fbb67-gs5nm.accounting",
      "service_name": "accounting",
      "service_namespace": "otel-demo",
      "service_version": "2.2.0",
      "telemetry_distro_name": "opentelemetry-ebpf-instrumentation",
      "telemetry_distro_version": "v0.9.0",
      "telemetry_sdk_language": "dotnet",
      "telemetry_sdk_name": "opentelemetry",
      "telemetry_sdk_version": "v1.43.0"
    }
    ```

## 2. Structural Observations

1.  **Dual-Labeling Gap**: Our Alloy pipeline successfully adds `cluster`, `namespace`, and `pod` to scraped metrics. However, Beyla metrics (from the `obi` agent) arrive via OTLP and lack these legacy labels.
2.  **Missing k8s_* on Scraped Metrics**: Currently, the `k8s_`-prefixed labels (e.g., `k8s_namespace_name`) are **NOT** showing up on scraped metrics in Mimir, even though they are defined in the ConfigMap. This suggests that Mimir might be ignoring them during the OTLP-to-Prometheus mapping if the non-prefixed versions already exist.
3.  **Discovery Identity**: The `obi` (Beyla) agent is correctly extracting deep Kubernetes metadata (Owner, ReplicaSet, SDK Language) which is currently unavailable to scraped metrics.

---
*Generated on: 2026-05-20*
