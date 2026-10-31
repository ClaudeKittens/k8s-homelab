# services

Workloads deployed into the clusters built under `vms/`. Each service is installed from an upstream Helm chart with a local `values.yaml`, pinned to a chart version in its justfile.

By default the justfiles talk to the `k3s-server` Lima VM from `vms/lima/k3s-templates` via its copied kubeconfig. Set `KUBECONFIG` to target a different cluster.

| Directory | What |
|-----------|------|
| `monitoring/` | Metrics and logs: VictoriaMetrics + Grafana |
