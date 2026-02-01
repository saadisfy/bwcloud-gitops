## Typical Errors and Fixes

- i am struggling with Argo CD apps not updating / "ComparisonError" and "SyncError"
  - What it was: AppSets and Applications were stuck with stale cache or invalid CRDs/config, so Argo CD couldn't reconcile.
  - How it was solved: Cleaned stale Apps (including finalizers), fixed CRD version mismatch by upgrading the OTel Operator chart, and corrected invalid OpenTelemetryCollector config format.

- i am struggling with duplicated Ingress resources (mimir/argocd)
  - What it was: Old `*-prod-*` Ingresses were still present from earlier naming scheme.
  - How it was solved: Removed old `*-prod-*` resources and standardized naming; ensured only one Ingress per app.

- i am struggling with Mimir sync failures / webhook TLS errors
  - What it was: Leftover `mimir-prod-*` resources caused webhook certificate SAN mismatch.
  - How it was solved: Deleted the stale resources and the `certificate` secret, then restarted `mimir-rollout-operator` to regenerate correct TLS certs.

- i am struggling with Mimir chart dependency build errors
  - What it was: Referenced chart versions that do not exist.
  - How it was solved: Pinned to valid versions (`mimir-distributed 6.0.5`, `reloader 2.2.7`) and rebuilt dependencies.

- i am struggling with otel-operator SyncError (CRD invalid / config unmarshal)
  - What it was: CRD stored version mismatch and `spec.config` passed as a string instead of an object.
  - How it was solved: Upgraded the chart, recreated CRDs, and converted `spec.config` to YAML object form.

- i am struggling with OTLP exporter endpoint port warning (4317 vs 4318)
  - What it was: Java auto-instrumentation used OTLP HTTP but pointed to the gRPC port.
  - How it was solved: Changed exporter endpoint to `:4318` (OTLP HTTP).

- i am struggling with 404s when exporting logs/traces
  - What it was: Collector only had metrics pipeline; logs/traces exporters hit missing endpoints.
  - How it was solved: Disabled log and trace export in instrumentation (`OTEL_LOGS_EXPORTER=none`, `OTEL_TRACES_EXPORTER=none`).

- i am struggling with no metrics reaching Mimir
  - What it was: Java agent did not emit runtime metrics by default.
  - How it was solved: Enabled metrics export and runtime metrics (`OTEL_METRICS_EXPORTER=otlp`, `OTEL_INSTRUMENTATION_RUNTIME_METRICS_ENABLED=true`).

- i am struggling with "no such host" from the Collector to Mimir
  - What it was: Service name changed after `fullnameOverride`, but collector still used old name.
  - How it was solved: Updated collector exporter endpoint to `mimir-distributor.mimir.svc.cluster.local`.

- i am struggling with 401 Unauthenticated from Mimir
  - What it was: Missing tenant header for multi-tenancy.
  - How it was solved: Added `X-Scope-OrgID: "1"` to OTLP HTTP exporter and Grafana datasource.

- i am struggling with Grafana login not working (secret issue)
  - What it was: Admin password secret was inconsistent.
  - How it was solved: Regenerated and set admin password in `apps/grafana/prod/values.yaml`.

- i am struggling with Grafana 404 Not Found when querying Mimir
  - What it was: Datasource pointed to wrong path/endpoint and lacked tenant header.
  - How it was solved: Pointed datasource to `http://mimir-gateway.mimir.svc.cluster.local/prometheus` and added `X-Scope-OrgID: 1`.

- i am struggling with Spring Petclinic CrashLoopBackOff (Exit 137)
  - What it was: Memory limit too low causing OOM kills.
  - How it was solved: Increased memory limit to `1Gi`.

- i am struggling with "object has been modified" during Argo CD sync (Mimir)
  - What it was: Frequent controller updates caused resource version conflicts.
  - How it was solved: Enabled Argo CD `ServerSideApply` and `ApplyOutOfSyncOnly` for the Mimir ApplicationSet.

- i am struggling with Grafana rollout stuck / volume permission errors
  - What it was: `chown` failed on PVC and rolling update kept old pod.
  - How it was solved: Set deployment strategy to `Recreate`, disabled `initChownData`, and set proper security context.

- i am struggling with load generation for metrics
  - What it was: No traffic to app, no visible metrics.
  - How it was solved: Added a CronJob to hit the service every 5 minutes.
