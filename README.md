# k8s-homelab

Single-node Kubernetes cluster on a Mac Mini (Apple Silicon), managed entirely
with OpenTofu. The cluster runs inside a Lima VM and is deployed in two phases:

1. **bootstrap/** — installs k3s on the Lima VM and writes a kubeconfig to the host
2. **cluster/**   — deploys all Helm-based services on top of k3s

```
k8s-homelab/
├── vm/lima.yaml          Lima VM config (Ubuntu 22.04, 4 CPU, 8 GB, 50 GB)
├── bootstrap/            OpenTofu: installs k3s via null_resource/local-exec
│   ├── versions.tf
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── cluster/              OpenTofu: all services via helm_release
│   ├── versions.tf
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── cert-manager.tf   cert-manager with CRDs (prerequisite for OTel Operator)
│   ├── monitoring.tf     kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
│   ├── otel.tf           OpenTelemetry Operator + standalone Collector
│   ├── logging.tf        Loki (single-binary) + Promtail DaemonSet
│   └── gitops.tf         Flux CD controllers
└── README.md
```

---

## Prerequisites

| Tool | Install | Purpose |
|------|---------|---------|
| **Lima** | `brew install lima` | Runs the Linux VM (the one manual step) |
| **OpenTofu** | `brew install opentofu` | IaC engine |
| **kubectl** | `brew install kubectl` | Interact with the cluster from macOS |
| **Flux CLI** (optional) | `brew install fluxcd/tap/flux` | Bootstrap GitOps after cluster is up |

```sh
brew install lima opentofu kubectl
```

Verify versions:

```sh
limactl --version   # 1.0+
tofu --version      # 1.7+
kubectl version --client
```

---

## Step 1 — Start the Lima VM

Lima uses macOS's Virtualization Framework (`vmType: vz`) for near-native ARM
performance. The VM is Ubuntu 22.04 with 4 CPUs, 8 GB RAM, and a 50 GB disk.

```sh
# From the repository root
limactl start --name=k8s-homelab vm/lima.yaml
```

The `--name=k8s-homelab` flag sets the VM name that all subsequent
`limactl shell k8s-homelab ...` commands reference.

Watch Lima stream the cloud-init output. First boot takes 2–4 minutes while it
downloads the Ubuntu image and runs the provisioning script (installs curl,
open-iscsi, apparmor).

**Verify the VM is running:**

```sh
limactl list
# NAME          STATUS    SSH       VMTYPE    ARCH      CPUS    MEMORY    DISK
# k8s-homelab   Running   127.0.0.1:60022   vz   aarch64   4       8GiB      50GiB

# Open a shell inside the VM (optional sanity-check)
limactl shell k8s-homelab -- uname -a
```

---

## Step 2 — Bootstrap k3s

The bootstrap module connects to the VM via `limactl shell` and:

1. Downloads and runs the official k3s installer
2. Waits for the node to reach `Ready`
3. Copies `/etc/rancher/k3s/k3s.yaml` to `~/.kube/k3s-homelab.yaml`
4. Smoke-tests the API from the Mac host

```sh
cd bootstrap
tofu init
tofu apply
```

Example output tail:

```
null_resource.verify_cluster: Creation complete after 2s

Outputs:

kubeconfig_path           = "/Users/you/.kube/k3s-homelab.yaml"
kubectl_test_command      = "kubectl --kubeconfig=/Users/you/.kube/k3s-homelab.yaml get nodes"
cluster_module_apply_command = "tofu -chdir=../cluster apply -var=\"kubeconfig_path=...\""
```

**Verify:**

```sh
kubectl --kubeconfig=~/.kube/k3s-homelab.yaml get nodes
# NAME               STATUS   ROLES                  AGE   VERSION
# lima-k8s-homelab   Ready    control-plane,master   1m    v1.30.3+k3s1
```

> **Tip:** Set `KUBECONFIG=~/.kube/k3s-homelab.yaml` in your shell profile to
> avoid typing `--kubeconfig` on every command.

### Variables (bootstrap)

| Variable | Default | Description |
|----------|---------|-------------|
| `lima_vm_name` | `k8s-homelab` | Lima VM name (must match `--name` flag) |
| `k3s_version` | `v1.30.3+k3s1` | k3s release tag |
| `kubeconfig_dir` | `~/.kube` | Directory to write the kubeconfig |

---

## Step 3 — Deploy cluster services

The cluster module deploys all services in dependency order. cert-manager is
installed first because the OpenTelemetry Operator needs its webhook TLS
certificates before it can register its own webhooks.

```sh
# Get the kubeconfig path from bootstrap output
KUBECONFIG_PATH=$(tofu -chdir=bootstrap output -raw kubeconfig_path)

cd cluster
tofu init
tofu apply -var="kubeconfig_path=$KUBECONFIG_PATH"
```

Or to customise the Grafana password:

```sh
tofu apply \
  -var="kubeconfig_path=$KUBECONFIG_PATH" \
  -var="grafana_admin_password=my-secure-password"
```

This installs (in dependency order):

1. **cert-manager** — webhook TLS cert issuer
2. **kube-prometheus-stack** — Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics
3. **OpenTelemetry Operator** — CRDs + controller (depends on cert-manager)
4. **OpenTelemetry Collector** — OTLP gateway + Prometheus scraper
5. **Loki** — log storage (single-binary mode)
6. **Promtail** — per-node log shipper → Loki
7. **Flux CD** — GitOps controllers

Total apply time is roughly 10–15 minutes on the first run (image pulls).

**Verify:**

```sh
export KUBECONFIG=~/.kube/k3s-homelab.yaml

kubectl get pods -A
# NAMESPACE       NAME                                              READY   STATUS
# cert-manager    cert-manager-...                                  1/1     Running
# monitoring      kube-prometheus-stack-grafana-...                 1/1     Running
# monitoring      prometheus-kube-prometheus-stack-prometheus-0     2/2     Running
# opentelemetry   otel-collector-...                                1/1     Running
# opentelemetry   opentelemetry-operator-...                        1/1     Running
# logging         loki-0                                            1/1     Running
# logging         promtail-...                                      1/1     Running
# flux-system     helm-controller-...                               1/1     Running
# ...
```

### Variables (cluster)

| Variable | Default | Description |
|----------|---------|-------------|
| `kubeconfig_path` | `~/.kube/k3s-homelab.yaml` | Path to kubeconfig |
| `grafana_admin_password` | `homelab-admin` | Grafana admin password |
| `grafana_persistence_size` | `5Gi` | Grafana PVC size |
| `prometheus_retention` | `7d` | How long Prometheus keeps metrics |
| `prometheus_storage_size` | `20Gi` | Prometheus TSDB PVC size |
| `loki_storage_size` | `20Gi` | Loki log storage PVC size |
| `otel_collector_memory_limit_mib` | `512` | OTel Collector hard memory limit |

---

## Accessing Grafana

Grafana is exposed only inside the cluster. Access it via `kubectl port-forward`:

```sh
export KUBECONFIG=~/.kube/k3s-homelab.yaml

kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Open **http://localhost:3000** in a browser.

| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | value of `grafana_admin_password` variable (default: `homelab-admin`) |

> Run the port-forward command in a dedicated terminal tab — it stays open until
> you Ctrl-C it. Run it in the background with `&` if you prefer.

### Pre-configured datasources

| Datasource | URL (cluster-internal) |
|------------|------------------------|
| Prometheus | `http://kube-prometheus-stack-prometheus.monitoring:9090` |
| Loki | `http://loki.logging:3100` |

Both datasources are configured automatically by the Helm values.

### Useful Grafana dashboards (import by ID)

| Dashboard | Grafana ID |
|-----------|-----------|
| Kubernetes / Compute Resources / Cluster | 15757 |
| Kubernetes / Nodes | 1860 |
| Loki / Chunks | 13407 |
| OpenTelemetry Collector | 15983 |

---

## Accessing other services

```sh
export KUBECONFIG=~/.kube/k3s-homelab.yaml

# Prometheus UI — http://localhost:9090
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

# Alertmanager — http://localhost:9093
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093

# Loki (direct query) — http://localhost:3100
kubectl -n logging port-forward svc/loki 3100:3100

# OTel Collector OTLP gRPC — localhost:4317
kubectl -n opentelemetry port-forward svc/otel-collector-opentelemetry-collector 4317:4317

# OTel Collector OTLP HTTP — http://localhost:4318
kubectl -n opentelemetry port-forward svc/otel-collector-opentelemetry-collector 4318:4318
```

---

## Sending data to the OTel Collector

The OTel Collector accepts OTLP on two endpoints (after port-forwarding):

| Protocol | Endpoint |
|----------|----------|
| gRPC | `localhost:4317` |
| HTTP | `http://localhost:4318` |

Example — send a test trace with `otelcli`:

```sh
brew install equinix-labs/otel-cli/otel-cli

# Port-forward the collector first (background)
kubectl -n opentelemetry port-forward svc/otel-collector-opentelemetry-collector 4317:4317 &

# Send a test span
otelcli exec \
  --endpoint localhost:4317 \
  --service my-test-service \
  --name "test-span" \
  -- echo "Hello from otelcli"
```

The Collector scrapes any Pod with these annotations:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"       # defaults to the Pod IP port
  prometheus.io/path: "/metrics"   # defaults to /metrics
```

---

## GitOps with Flux

After the cluster module is applied, connect Flux to a Git repository:

```sh
export KUBECONFIG=~/.kube/k3s-homelab.yaml

# Check Flux controllers are running
flux check

# Bootstrap against a GitHub personal repo
flux bootstrap github \
  --owner=<your-github-username> \
  --repository=homelab-gitops \
  --branch=main \
  --path=clusters/homelab \
  --personal
```

Flux will create the repo (if it doesn't exist), commit the cluster manifests,
and start reconciling. Add `HelmRelease` or `Kustomization` manifests to the
repo under `clusters/homelab/` and Flux will apply them automatically.

---

## Upgrading k3s

Change the `k3s_version` variable in `bootstrap/variables.tf` (or via
`-var`), then re-apply:

```sh
cd bootstrap
tofu apply -var="k3s_version=v1.31.0+k3s1"
```

The bootstrap module detects the version change (via `triggers`) and re-runs
the installer, which performs an in-place k3s upgrade.

---

## Upgrading Helm charts

Update the `version` field in the relevant `.tf` file and re-apply:

```sh
cd cluster
# Edit monitoring.tf: version = "59.0.0"
tofu apply
```

---

## Stopping and restarting the VM

```sh
limactl stop k8s-homelab    # graceful shutdown
limactl start k8s-homelab   # restart (reuses existing disk — fast)
```

k3s starts automatically when the VM boots (it is installed as a systemd
service). Wait ~30 seconds after `limactl start` for the API server to come up,
then all `kubectl` commands work again.

---

## Destroying everything

```sh
# 1. Destroy cluster services
cd cluster && tofu destroy

# 2. Destroy k3s (bootstrap resources are mostly local-exec; this cleans state)
cd ../bootstrap && tofu destroy

# 3. Delete the VM (WARNING: destroys all data on the 50 GB virtual disk)
limactl delete k8s-homelab
```

---

## Troubleshooting

### `limactl shell` hangs or times out

The VM may be stopped. Check with `limactl list`. If status is `Stopped`, run
`limactl start k8s-homelab` and wait for it to reach `Running`.

### `kubectl get nodes` returns `connection refused`

k3s may still be starting after a VM reboot. Wait 20–30 seconds and retry.
Check inside the VM: `limactl shell k8s-homelab -- sudo systemctl status k3s`

### Pod stuck in `Pending`

On a single-node cluster with resource-heavy charts, the node may be out of
CPU/memory. Check:

```sh
kubectl describe node
kubectl top node   # requires metrics-server (bundled with kube-prometheus-stack)
```

Consider increasing `cpus` or `memory` in `vm/lima.yaml` then running
`limactl stop k8s-homelab && limactl start k8s-homelab`.

### cert-manager webhook errors during `tofu apply`

cert-manager webhooks can take 30–60 seconds to become ready after installation.
If a subsequent resource (e.g. the OTel Operator) fails with a webhook timeout,
wait a minute and re-run `tofu apply`. The `wait = true` setting on the
cert-manager Helm release should prevent this in most cases.

### Helm chart versions

The chart versions in this repository were pinned at the time of writing. Check
for newer stable releases before deploying to a long-running cluster:

- cert-manager: https://github.com/cert-manager/cert-manager/releases
- kube-prometheus-stack: https://github.com/prometheus-community/helm-charts/releases
- opentelemetry-helm-charts: https://github.com/open-telemetry/opentelemetry-helm-charts/releases
- loki: https://github.com/grafana/loki/releases
- promtail: https://github.com/grafana/helm-charts/releases
- flux2: https://github.com/fluxcd-community/helm-charts/releases
