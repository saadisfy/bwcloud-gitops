## Typical Errors and Fixes

**Sections:** [argocd](#section-argocd) · [grafana](#section-grafana) · [mimir](#section-mimir) · [otel-operator](#section-otel-operator) · [spring-petclinic](#section-spring-petclinic) · [kargo](#section-kargo) · [argocd and mimir](#section-argocd-and-mimir) · [grafana and mimir](#section-grafana-and-mimir) · [otel-operator and mimir](#section-otel-operator-and-mimir)

### section: argocd

- i am struggling with Argo CD apps not updating / "ComparisonError" and "SyncError"
  - What it was: AppSets and Applications were stuck with stale cache or invalid CRDs/config, so Argo CD couldn't reconcile.
  - How it was solved: Cleaned stale Apps (including finalizers), fixed CRD version mismatch by upgrading the OTel Operator chart, and corrected invalid OpenTelemetryCollector config format.

- i am struggling with duplicated Ingress resources (mimir/argocd) (see section: argocd and mimir)
  - What it was: See section: argocd and mimir.
  - How it was solved: See section: argocd and mimir.

- i am struggling with "object has been modified" during Argo CD sync (Mimir) (see section: argocd and mimir)
  - What it was: See section: argocd and mimir.
  - How it was solved: See section: argocd and mimir.

### section: grafana

- i am struggling with Grafana login not working (secret issue)
  - What it was: Admin password secret was inconsistent.
  - How it was solved: Regenerated and set admin password in `apps/grafana/prod/values.yaml`.

- i am struggling with Grafana password drifting after redeploy (secret vs DB mismatch)
  - What it was: Grafana stores admin password in SQLite; changing the secret or pod env does not update the DB. Login kept failing despite correct secret.
  - How it was solved: Pinned `grafana.adminPassword` in stage values, ensured postStart resets password to env, and in worst case deleted the PVC to re‑init DB from the secret.

- i am struggling with Grafana rollout stuck / volume permission errors
  - What it was: `chown` failed on PVC and rolling update kept old pod.
  - How it was solved: Set deployment strategy to `Recreate`, disabled `initChownData`, and set proper security context.

- i am struggling with Grafana dependency / chart not vendored (same as Kargo)
  - What it was: Grafana prod had no Chart.lock and no charts/ in git (same pattern as Kargo), so Argo CD had to fetch the chart externally.
  - How it was solved: Ran `helm dependency build` in apps/grafana/prod, committed Chart.lock and charts/grafana-8.8.2.tgz, then pushed.

- i am struggling with Grafana 404 Not Found when querying Mimir (see section: grafana and mimir)
  - What it was: See section: grafana and mimir.
  - How it was solved: See section: grafana and mimir.

- i am struggling with Grafana datasource missing tenant header (X-Scope-OrgID) (see section: grafana and mimir)
  - What it was: See section: grafana and mimir.
  - How it was solved: See section: grafana and mimir.

### section: mimir

- i am struggling with Mimir sync failures / webhook TLS errors
  - What it was: Leftover `mimir-prod-*` resources caused webhook certificate SAN mismatch.
  - How it was solved: Deleted the stale resources and the `certificate` secret, then restarted `mimir-rollout-operator` to regenerate correct TLS certs.

- i am struggling with Mimir chart dependency build errors
  - What it was: Referenced chart versions that do not exist.
  - How it was solved: Pinned to valid versions (`mimir-distributed 6.0.5`, `reloader 2.2.7`) and rebuilt dependencies.

- i am struggling with duplicated Ingress resources (mimir/argocd) (see section: argocd and mimir)
  - What it was: See section: argocd and mimir.
  - How it was solved: See section: argocd and mimir.

- i am struggling with "object has been modified" during Argo CD sync (Mimir) (see section: argocd and mimir)
  - What it was: See section: argocd and mimir.
  - How it was solved: See section: argocd and mimir.

- i am struggling with Grafana 404 Not Found when querying Mimir (see section: grafana and mimir)
  - What it was: See section: grafana and mimir.
  - How it was solved: See section: grafana and mimir.

- i am struggling with Grafana datasource missing tenant header (X-Scope-OrgID) (see section: grafana and mimir)
  - What it was: See section: grafana and mimir.
  - How it was solved: See section: grafana and mimir.

- i am struggling with "no such host" from the Collector to Mimir (see section: otel-operator and mimir)
  - What it was: See section: otel-operator and mimir.
  - How it was solved: See section: otel-operator and mimir.

- i am struggling with 401 Unauthenticated from Mimir (see section: otel-operator and mimir)
  - What it was: See section: otel-operator and mimir.
  - How it was solved: See section: otel-operator and mimir.

### section: otel-operator

- i am struggling with otel-operator SyncError (CRD invalid / config unmarshal)
  - What it was: CRD stored version mismatch and `spec.config` passed as a string instead of an object.
  - How it was solved: Upgraded the chart, recreated CRDs, and converted `spec.config` to YAML object form.

- i am struggling with OTLP exporter endpoint port warning (4317 vs 4318)
  - What it was: Java auto-instrumentation used OTLP HTTP but pointed to the gRPC port (4317). OTLP HTTP uses port 4318.
  - How it was solved: In the Instrumentation CR (`apps/otel-operator/prod/templates/instrumentation-java.yaml`) set exporter endpoint to `http://...:4318`. Apps like Spring Petclinic that use this Instrumentation then get the correct `OTEL_EXPORTER_OTLP_ENDPOINT`; see section: spring-petclinic for app-side enable/disable.

- i am struggling with 404s when exporting logs/traces
  - What it was: Collector only had metrics pipeline; logs/traces exporters hit missing endpoints.
  - How it was solved: Disabled log and trace export in instrumentation (`OTEL_LOGS_EXPORTER=none`, `OTEL_TRACES_EXPORTER=none`).

- i am struggling with no metrics reaching Mimir
  - What it was: Java agent did not emit runtime metrics by default.
  - How it was solved: Enabled metrics export and runtime metrics (`OTEL_METRICS_EXPORTER=otlp`, `OTEL_INSTRUMENTATION_RUNTIME_METRICS_ENABLED=true`).

- i am struggling with "no such host" from the Collector to Mimir (see section: otel-operator and mimir)
  - What it was: See section: otel-operator and mimir.
  - How it was solved: See section: otel-operator and mimir.

- i am struggling with 401 Unauthenticated from Mimir (see section: otel-operator and mimir)
  - What it was: See section: otel-operator and mimir.
  - How it was solved: See section: otel-operator and mimir.

### section: spring-petclinic

- i am struggling with Spring Petclinic deployment not working in the Helm chart over GitOps
  - What I asked: "spring-petclinic deployment funktioniert nicht in der helm chart über gitops, probier alles mögliche aus bis es funktioniert … überprüf über argocd cli, kubectl cli bis es funktioniert"
  - What it was: **ImagePullBackOff** – the image `ghcr.io/saadisfy/spring-petclinic:latest` was not pullable (private or missing). Argo CD showed the app as Degraded; the deployment had 0/1 READY. Also `apps/spring-petclinic/base/values.yaml` had a duplicated block (same content twice).
  - How it was solved: Switched to a public image `docker.io/arey/springboot-petclinic:latest` in base/values.yaml; removed the duplicate block in base/values.yaml; added optional `imagePullSecrets` support in the deployment template for private GHCR later. When `springcommunity/spring-petclinic:latest` was tried it did not exist on Docker Hub, so pinned to `arey/springboot-petclinic`. Committed, pushed, synced Argo CD; deployment became 1/1 READY.

- i am struggling with Spring Petclinic CrashLoopBackOff (Exit 137)
  - What it was: Memory limit too low causing OOM kills.
  - How it was solved: Increased memory limit to `1Gi`.

- i am struggling with Spring Petclinic still not working (CrashLoopBackOff after image fix)
  - What I asked: "something is still not working for petclinic"
  - What it was: Pod was in **CrashLoopBackOff**; container started then crashed repeatedly. OTel Java auto-instrumentation was injected (init container + JAVA_TOOL_OPTIONS); logs showed OTLP port warning (4317 vs 4318 for http/protobuf). Likely causes: Java agent + old Spring Boot image or insufficient memory (256Mi request / 512Mi limit).
  - How it was solved: Added `otelInstrumentation.enabled` (default `false`) and made the OTel annotations conditional in the deployment template; set `enabled: false` so the app runs without the Java agent. Increased memory to 512Mi request and 768Mi limit. After sync and new pod, deployment became 1/1 READY and Healthy. Port fix lives in otel-operator Instrumentation CR (see section: otel-operator).

- i am struggling with wanting OTel injection back in Spring Petclinic, correct port, and app restart
  - What I asked: "ich möchte otel injection aber drinnen haben, das ist der ganze sinn der anwendung. fix den port problem und enable das instrumentation und lass starte anwendung neu"
  - What it was: OTel injection had been disabled for stability; user wanted it enabled again. The Instrumentation CR in otel-operator already used endpoint with port **4318** (OTLP HTTP); no code change was needed for the port – only re-enabling injection (see section: otel-operator for 4317 vs 4318).
  - How it was solved: Set `otelInstrumentation.enabled: true` in `apps/spring-petclinic/base/values.yaml`; committed and pushed; ran `argocd app sync spring-petclinic` and `kubectl rollout restart deployment/spring-petclinic -n spring-petclinic`. New pod came up with `OTEL_EXPORTER_OTLP_ENDPOINT` pointing to `:4318`; app stayed 1/1 Running and Healthy. README updated to state OTel is enabled and endpoint is :4318.

- i am struggling with load generation for metrics (Spring Petclinic)
  - What it was: No traffic to app, no visible metrics.
  - How it was solved: Added a CronJob to hit the service every 5 minutes.

### section: kargo

- i am struggling with Kargo deployment / Kargo app not deploying
  - What it was: Wrong OCI chart version (0.1.0 does not exist), no vendored dependency (Chart.lock and charts/ missing), so Argo CD could not resolve the Kargo Helm chart.
  - How it was solved: Set kargo dependency to valid version 1.8.4 in Chart.yaml; ran `helm dependency build` in apps/kargo/prod to create Chart.lock and charts/kargo-1.8.4.tgz; documented required api.adminAccount.passwordHash and tokenSigningKey in base/prod values and README.

- i am struggling with Kargo API panic (ADMIN_ACCOUNT_TOKEN_SIGNING_KEY missing value)
  - What it was: Kargo API requires env vars from api.adminAccount.passwordHash and tokenSigningKey; values were either missing or not passed to the subchart (wrapper chart expects values under the key kargo:).
  - How it was solved: Set kargo.api.adminAccount.passwordHash and kargo.api.adminAccount.tokenSigningKey in apps/kargo/prod/values.yaml (under kargo: for the wrapper subchart); generated bcrypt hash and signing key; documented initial admin password in README.

- i am struggling with Kargo promotion error "type v1alpha1.Chart has no field AppVersion"
  - What it was: Promotion template used `chartFrom(...).AppVersion`, which is not supported (only `Version` is available).
  - How it was solved: Removed AppVersion usage and relied on chart version or other inputs; promotion no longer referenced AppVersion.

- i am struggling with Kargo promotion not working via kubectl (no promotion steps)
  - What it was: Creating a Promotion via kubectl did not expand steps from the Stage template (webhook limitation).
  - How it was solved: Used `kargo promote` CLI (or UI) to create the Promotion so steps are populated correctly.

- i am struggling with Kargo promotion git-push config error (branch not allowed)
  - What it was: `git-push` step used `branch` instead of `targetBranch`.
  - How it was solved: Switched to `targetBranch` in Kargo promotion steps.

- i am struggling with Kargo Warehouse not discovering commits
  - What it was: `includePaths` filter was too narrow and Warehouse returned "No commits discovered".
  - How it was solved: Adjusted `includePaths` to match actual files and refreshed the Warehouse.

- i am struggling with Kargo webhooks-server patch failing (spec.selector field is immutable)
  - What it was: Deployment spec.selector is immutable in Kubernetes; after a Kargo chart upgrade the new manifest had a different selector, so the patch failed.
  - How it was solved: Deleted the existing Deployment (`kubectl delete deployment kargo-webhooks-server -n kargo`); Argo CD recreated it on next sync. Documented the command in README under Kargo troubleshooting.

- i am struggling with Kargo ingress missing and Secret under Argo CD application not syncing
  - What it was: No Ingress configured for Kargo API; the Secret kargo-api (admin credentials) was reported OutOfSync because the chart uses stringData and Kubernetes stores it as base64 data, so Argo CD saw a permanent diff.
  - How it was solved: Added Kargo API ingress in apps/kargo/prod/values.yaml (host: kargo.saadisfy.me, ingress enabled, nginx, cert-manager TLS with secretName kargo-tls). Added ignoreDifferences for the Secret kargo-api on .data in appsets/kargo.yaml so Argo CD stops treating it as OutOfSync.

### section: argocd and mimir

- i am struggling with duplicated Ingress resources (mimir/argocd)
  - What it was: Old `*-prod-*` Ingresses were still present from earlier naming scheme.
  - How it was solved: Removed old `*-prod-*` resources and standardized naming; ensured only one Ingress per app.

- i am struggling with "object has been modified" during Argo CD sync (Mimir)
  - What it was: Frequent controller updates caused resource version conflicts.
  - How it was solved: Enabled Argo CD `ServerSideApply` and `ApplyOutOfSyncOnly` for the Mimir ApplicationSet.

### section: grafana and mimir

- i am struggling with Grafana 404 Not Found when querying Mimir
  - What it was: Datasource pointed to wrong path/endpoint.
  - How it was solved: Pointed datasource to `http://mimir-gateway.mimir.svc.cluster.local/prometheus`.

- i am struggling with Grafana datasource missing tenant header (X-Scope-OrgID)
  - What it was: Mimir requires a tenant header for multi-tenancy.
  - How it was solved: Added `X-Scope-OrgID: 1` to the Grafana datasource.

### section: otel-operator and mimir

- i am struggling with "no such host" from the Collector to Mimir
  - What it was: Service name changed after `fullnameOverride`, but collector still used old name.
  - How it was solved: Updated collector exporter endpoint to `mimir-distributor.mimir.svc.cluster.local`.

- i am struggling with 401 Unauthenticated from Mimir
  - What it was: Missing tenant header for multi-tenancy.
  - How it was solved: Added `X-Scope-OrgID: "1"` to the OTLP HTTP exporter.
