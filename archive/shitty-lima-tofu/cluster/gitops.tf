# ── Flux CD ───────────────────────────────────────────────────────────────────
#
# Flux is a GitOps toolkit that continuously reconciles the cluster state with
# a Git repository. Once bootstrapped, you commit Kubernetes manifests (or
# HelmRelease / Kustomization resources) to a repo and Flux applies them.
#
# This Helm chart installs the core Flux controllers:
#   - source-controller     — fetches Git repos, Helm repos, OCI artifacts
#   - kustomize-controller  — applies Kustomization resources
#   - helm-controller       — reconciles HelmRelease resources
#   - notification-controller — sends alerts to Slack/Teams/etc.
#
# Chart: https://fluxcd-community.github.io/helm-charts  (flux2/flux2)
# Version pinned to: 2.12.2
#   Check for updates: https://github.com/fluxcd-community/helm-charts/releases
#
# ── Post-install: connecting Flux to a Git repo ───────────────────────────────
#
# After `tofu apply`, connect Flux to your homelab Git repository:
#
#   export KUBECONFIG=~/.kube/k3s-homelab.yaml
#
#   # GitHub example (SSH key will be generated and printed — add it as a deploy key)
#   flux bootstrap github \
#     --owner=<your-gh-username> \
#     --repository=homelab-gitops \
#     --branch=main \
#     --path=clusters/homelab \
#     --personal
#
#   # Generic Git (SSH) example
#   flux bootstrap git \
#     --url=ssh://git@git.example.com/homelab-gitops.git \
#     --branch=main \
#     --path=clusters/homelab
#
# Alternatively, just use the Helm-installed controllers without the CLI
# bootstrap step by creating GitRepository + Kustomization CRs manually.

resource "helm_release" "flux2" {
  name             = "flux2"
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  version          = "2.12.2"
  namespace        = "flux-system"
  create_namespace = true

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      # Flux controller resource requests — intentionally modest for homelab.
      helmController = {
        resources = {
          requests = { cpu = "100m", memory = "64Mi" }
          limits   = { memory = "512Mi" }
        }
      }

      sourceController = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { memory = "256Mi" }
        }
      }

      kustomizeController = {
        resources = {
          requests = { cpu = "100m", memory = "64Mi" }
          limits   = { memory = "512Mi" }
        }
      }

      notificationController = {
        resources = {
          requests = { cpu = "20m", memory = "32Mi" }
          limits   = { memory = "128Mi" }
        }
      }

      # Install Flux CRDs (GitRepository, HelmRelease, Kustomization, etc.)
      installCRDs = true

      # Log format — json is easier to query in Grafana/Loki
      logLevel = "info"
    })
  ]
}
