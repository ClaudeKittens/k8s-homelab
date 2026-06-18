# ── cert-manager ──────────────────────────────────────────────────────────────
#
# cert-manager is the cluster's TLS certificate authority and ACME client.
# It is installed FIRST because:
#   - The OpenTelemetry Operator requires cert-manager to issue webhook TLS certs.
#   - Any future Ingress / Gateway resources will use cert-manager Issuers.
#
# Chart: https://charts.jetstack.io  (jetstack/cert-manager)
# Version pinned to: 1.14.5
#   Check for updates: https://github.com/cert-manager/cert-manager/releases
#
# installCRDs=true lets the Helm chart manage the cert-manager CRDs.
# On upgrade, the chart updates the CRDs automatically.

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.14.5"
  namespace        = "cert-manager"
  create_namespace = true

  # wait=true blocks until all Pods are Running and webhooks are ready.
  # This is critical: downstream resources (OTel Operator) must not start
  # until cert-manager's webhook is accepting requests.
  wait    = true
  timeout = 300 # 5 minutes

  set {
    name  = "installCRDs"
    value = "true"
  }

  # Reduce log noise; set to "4" for verbose debugging.
  set {
    name  = "global.logLevel"
    value = "2"
  }

  # Resource requests/limits sized for a single-node homelab.
  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }
  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }
  set {
    name  = "resources.limits.memory"
    value = "256Mi"
  }

  # Webhook resource limits.
  set {
    name  = "webhook.resources.requests.cpu"
    value = "20m"
  }
  set {
    name  = "webhook.resources.requests.memory"
    value = "32Mi"
  }
  set {
    name  = "webhook.resources.limits.memory"
    value = "128Mi"
  }
}
