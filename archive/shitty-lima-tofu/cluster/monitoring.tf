# ── kube-prometheus-stack ─────────────────────────────────────────────────────
#
# The kube-prometheus-stack chart bundles:
#   - Prometheus Operator  — manages Prometheus / Alertmanager CRs
#   - Prometheus           — metrics collection and TSDB
#   - Alertmanager         — alert routing (no receivers configured by default)
#   - Grafana              — visualisation (access via port-forward, see outputs)
#   - kube-state-metrics   — cluster-level metrics (Deployments, Pods, etc.)
#   - node-exporter        — per-node OS / hardware metrics
#
# Chart: https://prometheus-community.github.io/helm-charts
# Version pinned to: 58.3.0
#   Check for updates: https://github.com/prometheus-community/helm-charts/releases
#
# Storage: k3s ships with the "local-path" StorageClass which provisions
# HostPath volumes automatically — no extra CSI driver needed.

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "58.3.0"
  namespace        = "monitoring"
  create_namespace = true

  wait    = true
  timeout = 600 # Prometheus Operator + all exporters can take a few minutes

  # Skip CRD installation on upgrade to avoid OpenTofu re-applying immutable fields.
  # The chart handles CRD updates gracefully on the first install.
  skip_crds = false

  values = [
    yamlencode({

      # ── Grafana ──────────────────────────────────────────────────────────────
      grafana = {
        adminPassword = var.grafana_admin_password

        # Persist dashboards, plugins, and Grafana's internal SQLite DB.
        persistence = {
          enabled          = true
          storageClassName = "local-path"
          size             = var.grafana_persistence_size
        }

        # Pre-configure the Loki datasource so it appears in Grafana immediately
        # once the logging module is applied.
        additionalDataSources = [
          {
            name      = "Loki"
            type      = "loki"
            url       = "http://loki.logging.svc.cluster.local:3100"
            access    = "proxy"
            isDefault = false
            jsonData = {
              maxLines = 5000
            }
          }
        ]

        # Resource limits for the Grafana Pod (single-node homelab sizing).
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { memory = "512Mi" }
        }

        # Useful Grafana plugins pre-installed at startup.
        plugins = [
          "grafana-piechart-panel",
          "grafana-clock-panel",
        ]

        # Grafana ini overrides — disable analytics pings, set default org.
        grafana_ini = {
          analytics = {
            reporting_enabled = false
            check_for_updates = false
          }
          "auth.anonymous" = {
            enabled  = false
          }
        }
      }

      # ── Prometheus ───────────────────────────────────────────────────────────
      prometheus = {
        prometheusSpec = {
          # Keep 7 days of metrics on a single-node cluster; tune upward if disk allows.
          retention = var.prometheus_retention

          # PVC-backed TSDB storage using k3s's built-in local-path provisioner.
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "local-path"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = { storage = var.prometheus_storage_size }
                }
              }
            }
          }

          # Resources for the Prometheus Pod.
          resources = {
            requests = { cpu = "200m", memory = "512Mi" }
            limits   = { memory = "2Gi" }
          }

          # Allow Prometheus to scrape ServiceMonitors/PodMonitors from any namespace.
          # Without this, only resources in the same namespace are scraped.
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false

          # Scrape interval — 30s is a reasonable homelab default.
          scrapeInterval = "30s"
          evaluationInterval = "30s"
        }
      }

      # ── Alertmanager ─────────────────────────────────────────────────────────
      alertmanager = {
        alertmanagerSpec = {
          resources = {
            requests = { cpu = "20m", memory = "64Mi" }
            limits   = { memory = "128Mi" }
          }
        }
      }

      # ── kube-state-metrics ───────────────────────────────────────────────────
      "kube-state-metrics" = {
        resources = {
          requests = { cpu = "20m", memory = "64Mi" }
          limits   = { memory = "256Mi" }
        }
      }

      # ── node-exporter ────────────────────────────────────────────────────────
      "prometheus-node-exporter" = {
        resources = {
          requests = { cpu = "20m", memory = "32Mi" }
          limits   = { memory = "64Mi" }
        }
      }
    })
  ]
}
