# Observability Architecture Design & Evaluation

This document outlines the architectural comparison, evaluation, and design considerations for the migration of dmTECH's observability stack. Based on the requirements defined in [Requirement_DM.md](file:///Users/saad.masood/Documents/Git/bwcloud-gitops/docs/ObservabilitySolutions/Requirement_DM.md), we compare three primary options: **Datadog**, **ELK (Elasticsearch & Kibana)**, and the **Grafana LGTM Stack**. We also detail the design of the open-source ELK stack integrated into our GitOps repository.

---

## 📊 Observability Stacks: Comparative Analysis

| Dimension | Datadog (SaaS) | ELK Stack (OSS / Self-Hosted) | Grafana LGTM Stack (OSS / Cloud) |
| :--- | :--- | :--- | :--- |
| **License & Cost** | Proprietary SaaS. High cost based on hosts, custom metrics, and log volume. | Elasticsearch & Kibana OSS (Apache 2.0) or Elastic License. Resource-heavy self-hosting. | AGPLv3 / Apache 2.0. Highly efficient self-hosting or Grafana Cloud SaaS. |
| **Storage & Scaling** | Fully managed by Datadog. No operational overhead. | Lucene index-based. Heavy memory/disk requirements. Sharding and index lifecycle management required. | Object storage-first (S3/GCS/MinIO). Metadata/index separated from chunk data, lowering cost. |
| **Agent / Collector** | Datadog Agent (proprietary, though agent code is open). | Logstash, Beats (Filebeat, Metricbeat), or OpenTelemetry. | Grafana Alloy / OpenTelemetry Collector. Standardized and highly interoperable. |
| **Dashboarding** | Rich, proprietary, out-of-the-box dashboards, highly integrated. | Kibana (very strong for log search/discover, weaker for custom time-series metrics). | Grafana (the industry standard for metric visualization and unified dashboards). |
| **Alerting** | Extremely rich alert rules, anomalies detection, and machine learning. | ElastAlert or Kibana Alerting (Kibana Alerting is license-restricted in OSS). | Grafana Alerting & Prometheus/Mimir Alertmanager. Configurable as code. |

---

## 🏗 Architectural Options for dmTECH

### 1. Datadog (The Premium SaaS Route)
* **Overview**: Fully managed cloud service.
* **Pros**: 
  * Near-zero maintenance overhead.
  * Best-in-class out-of-the-box correlation between APM, traces, logs, and infrastructure metrics.
  * Very easy setup for development teams.
* **Cons**:
  * Vendor lock-in (proprietary APIs and agents).
  * Extremely expensive for high-volume logs and high-cardinality custom metrics.
  * Data leaves the cluster/region (compliance/sovereignty concerns).

### 2. ELK Stack (The Classic Log Search Route)
* **Overview**: Deployed self-hosted or via Elastic Cloud.
* **Pros**:
  * Industry standard for full-text log search and analytics.
  * Highly mature query language (KQL/Lucene).
  * OSS versions (up to 7.10.2) or OpenSearch (Apache 2.0) are completely free of licensing fees.
* **Cons**:
  * Resource intensive: JVM overhead, high memory utilization, and heavy storage overhead due to full-text indexing.
  * Metric storage (Elasticsearch) is less efficient than TSDBs (Prometheus/Mimir) for long-term metric retention.

### 3. Grafana LGTM Stack (The Cloud-Native Observability Route)
* **Overview**: Composed of Loki (Logs), Grafana (Visualization), Tempo (Traces), and Mimir (Metrics).
* **Pros**:
  * OTLP-first and Kubernetes-native (via Grafana Alloy).
  * Highly decoupled components allow scaling individual pipelines (e.g., scale Loki independently of Mimir).
  * Low storage costs due to index-free logs (Loki) and chunk-based metrics (Mimir).
* **Cons**:
  * Steep learning curve for configuration (Alloy configurations, PromQL, LogQL).
  * Self-hosting requires robust GitOps operators (which we have successfully bootstrapped in this repo).

**Korrelation (Grundlagen):** Siehe [General/LGTM-Korrelation.md](General/LGTM-Korrelation.md) für Metrics → Traces → Logs, Schlüssel-Labels und Grafana-Navigation am Spring-Petclinic-Beispiel.

---

## 🛠 Deployed OSS ELK Implementation Details

To evaluate ELK alongside the existing LGTM stack, we have implemented a lightweight, open-source ELK deployment within this GitOps repository.

### 1. Deployed Components
* **Namespace**: `elk`
* **Elasticsearch OSS**: Deployed using version `7.10.2` (the last fully Apache-2.0 licensed version of Elasticsearch prior to the SSPL license transition).
  * Runs as a single-node cluster (`discovery.type=single-node`).
  * JVM options configured to `512MB` minimum/maximum heap sizes to ensure resource safety.
  * Volume backing: Temporary `emptyDir` for testing, configurable to PVC for persistence.
* **Kibana OSS**: Deployed using version `7.10.2`.
  * Connected to the local Elasticsearch service (`http://elasticsearch:9200`).
* **Grafana Integration**: Added as a unified datasource configuration in [values.yaml](file:///Users/saad.masood/Documents/Git/bwcloud-gitops/apps/grafana/base/values.yaml).

### 2. Grafana Datasource Configuration
```yaml
        - name: Elasticsearch
          type: elasticsearch
          access: proxy
          uid: elasticsearch
          url: http://elasticsearch.elk.svc.cluster.local:9200
          jsonData:
            timeField: "@timestamp"
            version: "7.10.0"
```

This setup allows logs stored in Elasticsearch to be queried directly in Grafana, enabling hybrid dashboards that fetch metrics from Mimir and logs from Elasticsearch.

---

## ⚡ Migration Strategy Recommendation

For dmTECH's transition to the cloud/new platform, we recommend a **Hybrid Cloud-Native Observability Strategy**:

1. **Telemetry Ingestion Layer (Grafana Alloy)**: Standardize on OpenTelemetry (OTLP) and Grafana Alloy. By using Alloy, the underlying backend remains completely pluggable. We can forward telemetry to Mimir/Loki, ELK, or Datadog simultaneously without modifying application configurations.
2. **Short-Term Evaluation**:
   * Deploy OpenSearch or ELK OSS inside the new platform to check if it satisfies log auditing/compliance needs.
   * Compare with Datadog during the summer phase (Juli–September) to measure total cost of ownership (TCO) vs operational overhead.
3. **Long-Term Target Architecture**: Use the self-managed LGTM stack (already built via this repository) as the primary internal telemetry platform, offering Grafana as the single pane of glass, and selectively integrate SaaS or Elasticsearch backends where full-text log analytics are required.
