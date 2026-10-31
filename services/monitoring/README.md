# services/monitoring

Grafana as the UI, VictoriaMetrics as the metrics backend. Everything runs in the `monitoring` namespace.

| Directory | Chart | Notes |
|-----------|-------|-------|
| `victoria-metrics/` | `vm/victoria-metrics-single` | Single-node VictoriaMetrics; scrapes the cluster with its built-in scrape config. Service: `victoria-metrics.monitoring.svc:8428` |
| `grafana/` | `grafana-community/grafana` | VictoriaMetrics provisioned as the default (Prometheus-type) datasource, plus the VictoriaMetrics self-monitoring dashboard |

## Usage

Requires `helm` and `kubectl`, and a running cluster (`just up` in `vms/lima/k3s-templates`).

```sh
# Install both
just install

# Or one at a time
just victoria-metrics/install
just grafana/install

# Grafana at http://localhost:3000, user admin
just grafana/password
just grafana/ui

# VictoriaMetrics UI at http://localhost:8428/vmui
just victoria-metrics/ui

# Remove both (data is kept)
just uninstall
```

## Persistence

Both use PVCs on k3s's default `local-path` StorageClass, which stores data on the VM's disk.

- Survives pod restarts, `helm uninstall`/reinstall, and stopping/starting the VM.
- Does **not** survive deleting the VM (`just down` in `vms/lima/k3s-templates`).

To delete the data for good, remove the PVCs: `kubectl delete pvc -n monitoring --all`.
