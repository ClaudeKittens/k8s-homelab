# vms/lima/ubuntu-24

Lima VM definition for Ubuntu 24.04 nodes. No cluster software is installed here — this layer only manages VM lifecycle and produces nodes ready to be bootstrapped by a cluster layer.

## Prerequisites

```sh
brew install socket_vmnet
sudo brew services start socket_vmnet
```

The `shared` network gives each VM an IP in the `192.168.105.0/24` range, reachable from the Mac host. For VMs to be reachable from other machines on your LAN, switch `lima: shared` to a bridged network in `node.yaml`.

## Usage

```sh
# Create and start a node
just up k3s-server

# Get its IP (hand this to the cluster layer)
just ip k3s-server

# Tear it down
just down k3s-server
```

## What this produces

A running Ubuntu 24.04 VM with:
- iptables in legacy mode (required by k3s)
- SSH accessible via `limactl shell <name>`
- A stable IP on the shared Lima network

The cluster layer (`cluster/k3s/`) takes the IP and SSH access from here and handles everything k3s-specific.
