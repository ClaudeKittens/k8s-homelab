# vms/lima/k3s-templates

Uses Lima's built-in `template:k3s` directly. Fastest path to a running cluster — no custom VM definition, no separate bootstrap step. k3s is installed as part of VM provisioning.

## Usage

```sh
# Create the server (first time only)
just create

# Start it again after a stop
just up

# Use kubectl
just kubectl k3s-server get nodes

# Get kubeconfig path for use with local kubectl
export KUBECONFIG=$(just kubeconfig k3s-server)
kubectl get nodes

# Tear down
just down k3s-server
```

## Tradeoffs

VM lifecycle and k3s bootstrap are coupled — this is intentional here since the point is speed, not flexibility. See `vms/lima/ubuntu-24/` for the decoupled approach.
