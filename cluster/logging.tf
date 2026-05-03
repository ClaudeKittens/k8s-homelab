# ── Loki ──────────────────────────────────────────────────────────────────────
#
# Grafana Loki is a log aggregation system designed to work alongside Prometheus.
# In single-binary mode, all Loki components (ingester, querier, compactor, etc.)
# run in one Pod — ideal for a single-node homelab.
#
# Logs flow:  Promtail → Loki → Grafana (Loki datasource, pre-configured)
#
# Chart: https://grafana.github.io/helm-charts  (grafana/loki)
# Version pinned to: 6.6.3
#   Check for updates: https://github.com/grafana/loki/releases
#
# Note: This is the *new* Loki chart (v6.x). The old loki-stack chart is
# deprecated. Promtail is deployed separately below.

resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = "6.6.3"
  namespace        = "logging"
  create_namespace = true

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      # ── Deployment mode ──────────────────────────────────────────────────────
      # SingleBinary packs all Loki microservices into one Deployment.
      # The distributed read/write/backend components are disabled.
      deploymentMode = "SingleBinary"

      loki = {
        # Disable multi-tenancy — all logs go into the default "fake" tenant.
        # Enables Promtail to push without an X-Scope-OrgID header.
        auth_enabled = false

        commonConfig = {
          # Replication factor 1 is correct for a single replica setup.
          replication_factor = 1
        }

        # Use local filesystem storage (no S3/GCS/Azure required).
        storage = {
          type = "filesystem"
        }

        # Ingester limits — relaxed for homelab use.
        limits_config = {
          reject_old_samples          = true
          reject_old_samples_max_age  = "168h" # 7 days
          retention_period            = "744h"  # 31 days
          ingestion_rate_mb           = 16
          ingestion_burst_size_mb     = 32
          max_query_series            = 5000
          max_query_parallelism       = 4
        }

        # Schema config — required in Loki 3.x.
        schemaConfig = {
          configs = [
            {
              from         = "2024-01-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "loki_index_"
                period = "24h"
              }
            }
          ]
        }
      }

      # ── SingleBinary component ────────────────────────────────────────────
      singleBinary = {
        replicas = 1

        persistence = {
          enabled          = true
          storageClass     = "local-path"
          size             = var.loki_storage_size
        }

        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { memory = "1Gi" }
        }
      }

      # ── Disable distributed components ────────────────────────────────────
      # Setting replicas=0 disables the dedicated read/write/backend pods
      # that are used in the distributed deployment mode.
      read    = { replicas = 0 }
      write   = { replicas = 0 }
      backend = { replicas = 0 }

      # ── Disable Loki's bundled Grafana/Prometheus (we have our own) ───────
      monitoring = {
        selfMonitoring = {
          enabled = false
          grafanaAgent = {
            installOperator = false
          }
        }
        lokiCanary = {
          enabled = false
        }
      }

      # ── Disable the built-in test pod ─────────────────────────────────────
      test = {
        enabled = false
      }
    })
  ]
}

# ── Promtail ──────────────────────────────────────────────────────────────────
#
# Promtail runs as a DaemonSet — one Pod per node — and tails all container
# log files from /var/log/pods on the node filesystem.
# It annotates each log entry with Pod / namespace / container metadata from
# the Kubernetes API, then ships the structured streams to Loki.
#
# Chart: https://grafana.github.io/helm-charts  (grafana/promtail)
# Version pinned to: 6.16.3
#   Check for updates: https://github.com/grafana/helm-charts/releases

resource "helm_release" "promtail" {
  name      = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart     = "promtail"
  version   = "6.16.3"
  namespace = "logging"

  # Loki must be running before Promtail starts shipping logs.
  depends_on = [helm_release.loki]

  wait    = true
  timeout = 180

  values = [
    yamlencode({
      # ── Loki push target ──────────────────────────────────────────────────
      config = {
        clients = [
          {
            # Point at the Loki Service inside the cluster.
            url = "http://loki.logging.svc.cluster.local:3100/loki/api/v1/push"
          }
        ]

        # ── Scrape config ────────────────────────────────────────────────────
        # The default Promtail config already tails /var/log/pods/**/*.log.
        # We add extra_relabel_configs to ensure useful labels are propagated.
        snippets = {
          extraRelabelConfigs = [
            # Carry the container name as a label for Grafana log panel filtering.
            {
              source_labels = ["__meta_kubernetes_pod_container_name"]
              target_label  = "container"
            }
          ]
        }
      }

      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }

      # Promtail needs to read host log files — mount /var/log from the node.
      # The chart does this by default; this confirms the setting explicitly.
      tolerations = [
        {
          operator = "Exists"  # tolerate all taints so Promtail runs on every node
          effect   = "NoSchedule"
        }
      ]
    })
  ]
}
