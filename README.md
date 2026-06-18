# k8s-homelab

A collection of experiments in running Kubernetes on home compute. Each top-level directory (outside of `archive/`) represents an isolated experiment with its own VM management, control plane setup, and node configuration approach.

## Structure

```
experiments/
  <name>/          # one directory per experiment
    README.md      # what this approach is, how to run it, lessons learned
    vm/            # VM provisioning (lima, UTM, Parallels, QEMU, ...)
    cluster/       # k8s control plane bootstrap (kubeadm, k3s, talos, ...)
    workloads/     # any workloads deployed into the cluster

.github/
  repo-settings/   # Terraform managing this GitHub repo's settings

archive/
  shitty-lima-tofu/  # original lima + OpenTofu attempt
```

## Experiments

| Directory | VMs | Control plane | Status |
|-----------|-----|---------------|--------|
| *(none yet)* | | | |

## Goals

- Understand the tradeoffs between different VM backends on Apple Silicon
- Compare lightweight distros (k3s, k0s, talos) vs full kubeadm clusters
- Figure out a setup that's easy to tear down and rebuild from scratch
