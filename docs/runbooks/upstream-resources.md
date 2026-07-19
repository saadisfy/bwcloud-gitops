# Upstream Resources Inventory

This document lists all upstream alerts, recording rules, and Grafana dashboards that have been downloaded into the workspace. These files are sourced from various official open-source projects and mixins.

## Mimir
**Rules & Alerts (saved in `apps/mimir/noctua/files/mimir/`):**
*   [alerts.yaml](https://raw.githubusercontent.com/grafana/mimir/main/operations/mimir-mixin-compiled/alerts.yaml)
*   [rules.yaml](https://raw.githubusercontent.com/grafana/mimir/main/operations/mimir-mixin-compiled/rules.yaml)

## Tempo
**Rules & Alerts (saved in `apps/mimir/noctua/files/tempo/`):**
*   [alerts.yaml](https://raw.githubusercontent.com/grafana/tempo/main/operations/tempo-mixin-compiled/alerts.yaml)
*   [rules.yaml](https://raw.githubusercontent.com/grafana/tempo/main/operations/tempo-mixin-compiled/rules.yaml)

## Loki
**Rules & Alerts (saved in `apps/mimir/noctua/files/loki/`):**
*   [alerts.yaml](https://raw.githubusercontent.com/grafana/loki/main/production/loki-mixin-compiled/alerts.yaml)
*   [rules.yaml](https://raw.githubusercontent.com/grafana/loki/main/production/loki-mixin-compiled/rules.yaml)

## Alloy
**Rules & Alerts (saved in `apps/mimir/noctua/files/alloy/`):**
*   [alloy_clustering.yaml](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/alerts/alloy_clustering.yaml)
*   [alloy_controller.yaml](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/alerts/alloy_controller.yaml)
*   [alloy_otelcol.yaml](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/alerts/alloy_otelcol.yaml)

**Dashboards (saved in `apps/grafana/noctua/files/alloy/dashboards/`):**
*   [alloy-cluster-node.json](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/dashboards/alloy-cluster-node.json)
*   [alloy-cluster-overview.json](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/dashboards/alloy-cluster-overview.json)
*   [alloy-controller.json](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/dashboards/alloy-controller.json)
*   [alloy-logs.json](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/dashboards/alloy-logs.json)
*   [alloy-loki.json](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/dashboards/alloy-loki.json)
*   [alloy-opentelemetry.json](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/dashboards/alloy-opentelemetry.json)
*   [alloy-otel-engine-overview.json](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/dashboards/alloy-otel-engine-overview.json)
*   [alloy-prometheus-remote-write.json](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/dashboards/alloy-prometheus-remote-write.json)
*   [alloy-resources.json](https://raw.githubusercontent.com/grafana/alloy/main/operations/alloy-mixin/rendered/dashboards/alloy-resources.json)

## Argo CD
**Dashboards (saved in `apps/grafana/noctua/files/argocd/dashboards/`):**
*   [dashboard.json](https://raw.githubusercontent.com/argoproj/argo-cd/master/examples/dashboard.json)

## Argo Rollouts
**Dashboards (saved in `apps/grafana/noctua/files/argorollouts/dashboards/`):**
*   [dashboard.json](https://raw.githubusercontent.com/argoproj/argo-rollouts/master/examples/dashboard.json)

## Kyverno
**Dashboards (saved in `apps/grafana/noctua/files/kyverno/dashboards/`):**
*   [kyverno-dashboard.json](https://raw.githubusercontent.com/kyverno/kyverno/main/charts/kyverno/charts/grafana/dashboard/kyverno-dashboard.json)

## Kubernetes (kube-prometheus)
**Rules & Alerts (saved in `apps/mimir/noctua/files/kubernetes/`):**
*   [alertmanager-alertmanager.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/alertmanager-alertmanager.yaml)
*   [alertmanager-networkPolicy.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/alertmanager-networkPolicy.yaml)
*   [alertmanager-podDisruptionBudget.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/alertmanager-podDisruptionBudget.yaml)
*   [alertmanager-prometheusRule.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/alertmanager-prometheusRule.yaml)
*   [alertmanager-secret.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/alertmanager-secret.yaml)
*   [alertmanager-service.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/alertmanager-service.yaml)
*   [alertmanager-serviceAccount.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/alertmanager-serviceAccount.yaml)
*   [alertmanager-serviceMonitor.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/alertmanager-serviceMonitor.yaml)
*   [grafana-prometheusRule.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/grafana-prometheusRule.yaml)
*   [kubePrometheus-prometheusRule.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/kubePrometheus-prometheusRule.yaml)
*   [kubeStateMetrics-prometheusRule.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/kubeStateMetrics-prometheusRule.yaml)
*   [kubernetesControlPlane-prometheusRule.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/kubernetesControlPlane-prometheusRule.yaml)
*   [nodeExporter-prometheusRule.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/nodeExporter-prometheusRule.yaml)
*   [prometheus-prometheusRule.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/prometheus-prometheusRule.yaml)
*   [prometheusOperator-prometheusRule.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/prometheusOperator-prometheusRule.yaml)

**Dashboards (saved in `apps/grafana/noctua/files/kubernetes/dashboards/`):**
*   [grafana-dashboardDefinitions.yaml](https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/grafana-dashboardDefinitions.yaml)