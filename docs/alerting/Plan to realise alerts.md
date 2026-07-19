# Plan: Realizing the Alerting Stack

This document outlines the prioritized, step-by-step implementation plan to establish a functional and stable alerting stack using Grafana Mimir and Grafana.

## 🏗 Target Architecture

1.  **Upstream Alerts:** Official Prometheus-format alerts (e.g., Mimir self-monitoring) are stored in `apps/mimir/prod/files/mimir/alerts.yaml`.
2.  **Rule Synchronization:** A GitOps Job (`mimir-ruler-rules-sync`) uses `mimirtool` to load these alerts into the **Mimir Ruler** under **Tenant 1**.
3.  **Alert Evaluation:** The **Mimir Ruler** evaluates these rules and sends firing alerts to the **Mimir Alertmanager**.
4.  **Notification Routing:** The **Mimir Alertmanager** routes alerts to external targets (e.g., Email, Slack). *Note: The previous idea of using Grafana as a direct ingestion endpoint for Ruler was discarded due to API incompatibilities.*
5.  **Grafana Managed Alerts:** Alerts created via the Grafana UI by teams are stored in `apps/grafana/prod/files/<team>/alert-rules-*.yaml` and provisioned via the Grafana Operator as `GrafanaAlertRuleGroup` CRDs.
6.  **Unified Visibility:** Grafana is configured with the Mimir Datasource (`manageAlerts: true`) and Mimir Alertmanager Datasource to provide a single pane of glass for all alerts.

---

## 📅 Implementation Steps

### Phase 1: Mimir Ruler Stability & Tenant Alignment

**Goal:** Fix the Ruler crash loop and align everything to **Tenant 1** (matching Alloy/OTel).

1.  **Update Mimir Production Values (`apps/mimir/prod/values.yaml`):**
    *   Change `rulerRuleSync.tenantId` from `anonymous` to `1`.
    *   Update the `initContainer` command to create the correct tenant directory: `mkdir -p /ruler-storage/1/rules`.
    *   Add `securityContext: { fsGroup: 10001 }` to the Ruler deployment to ensure the `EmptyDir` volume is writable by the non-root user.
    *   Point `mimir.structuredConfig.ruler.alertmanager_url` to the Mimir Alertmanager service: `http://mimir-alertmanager-headless.mimir.svc:8080`.
    *   Ensure `mimir.structuredConfig.ruler_storage.local.directory` is set to `/ruler-storage`.

### Phase 2: Synchronization Job Modernization

**Goal:** Ensure alert rules are successfully loaded into Mimir using a distroless-compatible method.

1.  **Update Sync Template (`apps/mimir/prod/templates/ruler-rules-sync.yaml`):**
    *   Maintain the architectural change that merges all rule files into a single `mimir-rules-bundle` ConfigMap.
    *   Ensure the `args` for `mimirtool` are correctly ordered: `rules load --address=... --id=1 /rules/rules.yaml`.
    *   Remove the `command` override to allow the pod to use the image's default entrypoint.

2.  **Organize Rule Files:**
    *   Ensure `apps/mimir/prod/files/mimir/alerts.yaml` contains only upstream Prometheus-format alerts.
    *   Ensure recording rules (if any) are placed in a separate file or correctly labeled within the merged rules.

### Phase 3: Grafana Integration

**Goal:** Enable Grafana to display and manage Mimir rules.

1.  **Update Grafana Production Values (`apps/grafana/prod/values.yaml`):**
    *   Configure the Mimir Datasource with:
        *   `uid: mimir`
        *   `jsonData.manageAlerts: true`
        *   `jsonData.alertmanagerUid: mimir-am`
        *   `httpHeaderName1: X-Scope-OrgID`
        *   `httpHeaderValue1: "1"`
    *   Add a new Datasource for the Mimir Alertmanager:
        *   `name: Mimir Alertmanager`
        *   `type: alertmanager`
        *   `uid: mimir-am`
        *   `url: http://mimir-alertmanager.mimir.svc:8080`
        *   `jsonData.handleGrafanaManagedAlerts: false`

2.  **Clean up Duplicate Templates:**
    *   Modify `apps/grafana/prod/templates/grafana-operator-managed-alerts-from-prometheus-files.yaml` to **ignore** files that are already handled by the Mimir `ruler-rules-sync` job.

### Phase 4: Alertmanager Configuration

**Goal:** Ensure Mimir Alertmanager is ready to route alerts.

1.  **Mimir Alertmanager Setup:**
    *   Verify that `mimir-distributed.alertmanager.enabled` is `true` in `apps/mimir/base/values.yaml`.
    *   Provision a basic Alertmanager configuration (receivers, routes) either via `fallbackConfig` in values or a dedicated sync job.

---

## 🧪 Validation & Testing

1.  **Check Pods:** Run `kubectl get pods -n mimir` to ensure Ruler and Alertmanager are `Running`.
2.  **Verify Rules:** Run `kubectl logs job/mimir-ruler-rules-sync -n mimir` to confirm rules were loaded successfully.
3.  **Check API:** Verify loaded rules via curl:
    `curl -H "X-Scope-OrgID: 1" http://mimir-gateway.mimir.svc.cluster.local/prometheus/config/v1/rules`
4.  **Check Grafana:**
    *   Navigate to **Alerting > Alert rules** in Grafana.
    *   Verify that "Mimir" rules (Tenant 1) are visible.
5.  **Test Notification:** Create a temporary alert that triggers immediately and confirm receipt at the configured contact point.

---

## 📝 Constraints & Technical Notes

*   **Tenant ID:** Always use `1` for internal metrics and alerts.
*   **Permissions:** Use `fsGroup: 10001` for all components mounting writable volumes in Mimir.
*   **GitOps Workflow:** Always use `git commit` and `git push`. Use `argocd app sync mimir` to trigger updates. Use `kubectl` for **read-only** observation only.
