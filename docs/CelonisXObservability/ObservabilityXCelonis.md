# Concept: Process Observability – Celonis x Grafana LGTM Stack

## 1. Executive Summary
This document outlines the strategic integration of **Celonis (Execution Management System / Process Mining)** with the **Grafana LGTM Stack (Loki, Grafana, Tempo, Mimir)** and **OpenTelemetry (OTel)**. By merging business process intelligence with technical observability, we create "Process Observability" – a unified view that correlates business KPIs (e.g., Order-to-Cash cycle time) with technical system health (e.g., SAP API latency, database load).

## 2. Theoretical Framework: The Convergence
| Dimension | Celonis (Process Mining) | Grafana LGTM (Observability) |
| :--- | :--- | :--- |
| **Focus** | Business Process Logic & Compliance | Technical Infrastructure & App Performance |
| **Data Source** | Event Logs from ERP/CRM (SAP, Salesforce) | Metrics, Traces, and System Logs |
| **Goal** | Identify process bottlenecks and inefficiencies | Identify technical failures and latency |
| **Target** | Business Analysts / Process Owners | DevOps / SRE / Platform Engineers |

**The Goal:** Correlate a "long-running invoice process" in Celonis with a "slow database query" or "high CPU on the extractor" in Grafana.

## 3. Architecture & Data Flow

### 3.1 Data Collection: The Extractor as the Observability Anchor
Since direct access to source systems (SAP/Oracle) is often restricted, we utilize the **on-prem Celonis Extractor** as our primary telemetry source:

1.  **Indirect Source Monitoring (eBPF & Network):** 
    *   **Beyla (eBPF):** Deployed on the Extractor host to monitor network interactions with SAP. This measures SAP response times (latency) without requiring SAP-side instrumentation or credentials.
2.  **Log-Derived Metrics (Loki):**
    *   **Extractor Log Parsing:** Scraping Extractor logs to capture events like "Querying Table X" or "Fetched Y rows". This allows us to infer source system activity and table growth rates indirectly.
3.  **Host & Application Monitoring (Alloy):**
    *   Standard resource monitoring (CPU, RAM, Disk) of the Extractor host to ensure extraction performance isn't bottlenecked by local hardware.
4.  **Cloud & Webhook Integration:**
    *   **Celonis IBC API:** Monitoring data job status and cloud-side ingestion.
    *   **Action Flow Webhooks:** Sending OTLP execution signals from Celonis automations to Grafana.

### 3.2 Signal Mapping
*   **Mimir (Metrics):**
    *   `celonis_extractor_sap_response_ms`: SAP latency measured from the Extractor (via Beyla).
    *   `celonis_data_latency_seconds`: Time gap between SAP timestamp (from logs) and Celonis availability.
    *   `celonis_extractor_row_throughput`: Ingestion speed derived from log parsing.
    *   `celonis_action_flow_duration_seconds`: Performance of automated actions.
    *   `celonis_api_request_latency`: Health of the Celonis IBC interface.
*   **Loki (Logs):**
    *   **Audit Logs:** Track who changed process models or data permissions.
    *   **Action Flow Logs:** Detailed execution paths for troubleshooting failed automations.
    *   **Extractor Logs:** Monitoring the "Last Mile" connection to source systems (SAP/Oracle).
*   **Tempo (Traces):**
    *   **Distributed Tracing:** Visualizing the path of a transaction from a User Request -> Source System -> Celonis Extractor -> Celonis IBC -> Action Flow -> Target System.
    *   **Span Attributes:** Injecting `process_id` or `invoice_number` as OTel attributes to link technical traces to business objects.

## 4. Feature Combinations & Use Cases

### 4.1 "The Process Health Dashboard"
A unified Grafana Dashboard combining:
*   **Top Row (Business):** Cycle time, Automation Rate (from Celonis).
*   **Middle Row (Technical):** API Response times, Webhook success rates (from OTel).
*   **Bottom Row (Infrastructure):** Resource usage of the Extractors/Connectors (from Mimir).

### 4.2 Intelligent Alerting
*   **Technical Trigger:** "Extractor CPU > 90% for 5 mins."
*   **Business Impact Alert:** "High risk of delayed Data Refresh for 'Procure-to-Pay' process. Predicted delay: 2 hours."
*   **Action Flow Loop:** Grafana Alert triggers a Celonis Action Flow to notify Process Owners or scale infrastructure.

### 4.3 Root Cause Analysis (RCA)
When a business KPI drops (e.g., "Manual Touches" increase):
1.  User clicks on the "KPI drop" in Grafana.
2.  Grafana uses **Data Links** to jump to the exact Trace in Tempo.
3.  Tempo shows that the SAP OData service was throwing 500 errors during that period, forcing users to manual workarounds.

## 5. Implementation Strategy in `bwcloud-gitops`

### Phase 1: Infrastructure Monitoring
*   Instrument Celonis Extractors using the `otel-instrumentation` skill.
*   Collect logs via `loki` and metrics via `alloy`.

### Phase 2: API & Webhook Integration
*   Configure Alloy to receive OTLP signals from Celonis Action Flows.
*   Use `otel-ottl` to transform Celonis-specific metadata into OTel Semantic Conventions.

### Phase 3: Correlation & Dashboards
*   Build a "Process Observability" dashboard in Grafana using the `dashboarding` skill.
*   Implement cross-datasource queries (Log-to-Metric, Trace-to-Log).

---
*Created as part of the bwcloud-gitops Observability Strategy.*
