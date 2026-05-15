# Kubernetes Dashboards Source

The Kubernetes dashboards in this directory are sourced from the [monitoring-mixins/website](https://github.com/monitoring-mixins/website) repository, which provides pre-rendered JSON files generated from the [kubernetes-monitoring/kubernetes-mixin](https://github.com/kubernetes-monitoring/kubernetes-mixin).

## Upstream Sources

| Dashboard | Upstream URL |
|-----------|--------------|
| Compute Resources / Cluster | [k8s-resources-cluster.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/k8s-resources-cluster.json) |
| Compute Resources / Namespace | [k8s-resources-namespace.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/k8s-resources-namespace.json) |
| Compute Resources / Node | [k8s-resources-node.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/k8s-resources-node.json) |
| Compute Resources / Pod | [k8s-resources-pod.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/k8s-resources-pod.json) |
| Compute Resources / Workload | [k8s-resources-workload.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/k8s-resources-workload.json) |
| Networking / Cluster | [k8s-resources-cluster.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/k8s-resources-cluster.json) (Note: Some metrics are shared) |
| System / API Server | [apiserver.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/apiserver.json) |
| System / Kubelet | [kubelet.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/kubelet.json) |
| System / Controller Manager | [controller-manager.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/controller-manager.json) |
| System / Scheduler | [scheduler.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/scheduler.json) |
| System / Proxy | [proxy.json](https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/kubernetes/dashboards/proxy.json) |

## Implementation Details

These dashboards rely on recording rules provided by the same mixin, which are deployed to the Mimir Ruler via `apps/mimir/prod/files/kubernetes/alerts-rules.yaml`.

The `cluster` variable is populated dynamically using:
`label_values(up{job="kube-state-metrics"}, cluster)`

All dashboards are configured to use the `mimir` datasource by default via the `${datasource}` variable.
