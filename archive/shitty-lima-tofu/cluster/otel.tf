# ── OpenTelemetry Operator ────────────────────────────────────────────────────
#
# The OpenTelemetry Operator extends Kubernetes with CRDs:
#   OpenTelemetryCollector — declarative collector deployment
#   Instrumentation         — auto-instrumentation injection for app Pods
#
# The Operator's admission webhook requires cert-manager to issue its TLS cert,
# so cert-manager must be Ready before this resource is created.
#
# Chart: https://open-telemetry.github.io/opentelemetry-helm-charts
# Version pinned to: 0.63.1
#   Check for updates: https://github.com/open-telemetry/opentelemetry-helm-charts/releases

resource "helm_release" "opentelemetry_operator" {
  name             = "opentelemetry-operator"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-operator"
  version          = "0.63.1"
  namespace        = "opentelemetry"
  create_namespace = true

  # cert-manager must have its webhooks running before the OTel Operator
  # can register its own validating/mutating webhooks.
  depends_on = [helm_release.cert_manager]

  wait    = true
  timeout = 300

  set {
    # Use the contrib collector image — it includes all receivers/exporters
    # including the Prometheus receiver used below.
    name  = "manager.collectorImage.repository"
    value = "otel/opentelemetry-collector-contrib"
  }

  set {
    name  = "manager.resources.requests.cpu"
    value = "50m"
  }
  set {
    name  = "manager.resources.requests.memory"
    value = "64Mi"
  }
  set {
    name  = "manager.resources.limits.memory"
    value = "256Mi"
  }
}

# ── OpenTelemetry Collector (standalone Helm deployment) ──────────────────────
#
# This deploys a Collector via the standalone Helm chart (not via the Operator
# CRD). Both the Operator and this Helm-deployed Collector co-exist:
#   - The Operator enables teams to deploy per-namespace collectors via CRDs.
#   - This standalone collector acts as the cluster-wide gateway, scraping
#     metrics from Prometheus-annotated Pods and accepting OTLP from apps.
#
# Pipeline overview:
#
#   Receivers:
#     otlp (grpc :4317, http :4318) ── accept traces, metrics, logs from apps
#     prometheus                     ── scrape Prometheus-annotated Pods
#
#   Processors:
#     memory_limiter   ── shed load before OOM; must run FIRST in the pipeline
#     batch            ── accumulate data to improve export efficiency
#
#   Exporters:
#     prometheus       ── re-expose scraped + received metrics on :8889
#                        (Prometheus can scrape this endpoint)
#     debug            ── log a summary of every received batch (basic verbosity)
#
# Chart: https://open-telemetry.github.io/opentelemetry-helm-charts
# Version pinned to: 0.100.0
#   Check for updates: https://github.com/open-telemetry/opentelemetry-helm-charts/releases

resource "helm_release" "opentelemetry_collector" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = "0.100.0"
  namespace  = "opentelemetry"

  # Operator must exist so its CRDs are installed before we apply collector config.
  depends_on = [helm_release.opentelemetry_operator]

  wait    = true
  timeout = 300

  values = [
    <<-YAML
    # Run as a single Deployment replica (not DaemonSet) since this is a
    # centralised gateway, not a per-node agent.
    mode: deployment
    replicaCount: 1

    # Use the contrib image — required for the prometheus receiver.
    image:
      repository: otel/opentelemetry-collector-contrib

    # Create a ClusterRole + binding so the Prometheus receiver can call the
    # Kubernetes API to discover scrape targets via pod annotations.
    clusterRole:
      create: true
      rules:
        - apiGroups: [""]
          resources: ["pods", "services", "endpoints", "nodes", "namespaces"]
          verbs: ["get", "list", "watch"]
        - apiGroups: [""]
          resources: ["nodes/metrics"]
          verbs: ["get"]
        - nonResourceURLs: ["/metrics", "/metrics/cadvisor"]
          verbs: ["get"]

    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        memory: ${var.otel_collector_memory_limit_mib}Mi

    # Expose ports used by the OTLP receivers and the Prometheus exporter.
    ports:
      otlp:
        enabled: true
        containerPort: 4317
        servicePort: 4317
        protocol: TCP
      otlp-http:
        enabled: true
        containerPort: 4318
        servicePort: 4318
        protocol: TCP
      metrics:
        enabled: true
        containerPort: 8888  # collector self-metrics
        servicePort: 8888
        protocol: TCP
      prom-exporter:
        enabled: true
        containerPort: 8889  # prometheus exporter (scraped by Prometheus)
        servicePort: 8889
        protocol: TCP

    # Annotate the Pod so kube-prometheus-stack's Prometheus scrapes the
    # collector's own metrics automatically.
    podAnnotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "8888"
      prometheus.io/path: "/metrics"

    config:
      receivers:
        # ── OTLP Receiver ───────────────────────────────────────────────────
        # Accept traces, metrics, and logs from any instrumented application
        # via gRPC (port 4317) or HTTP (port 4318).
        otlp:
          protocols:
            grpc:
              endpoint: "0.0.0.0:4317"
            http:
              endpoint: "0.0.0.0:4318"

        # ── Prometheus Receiver ─────────────────────────────────────────────
        # Scrapes two target sets:
        #   1. The collector's own internal metrics (self-monitoring).
        #   2. Any Pod with the "prometheus.io/scrape: true" annotation
        #      — the same annotation convention used by kube-prometheus-stack.
        prometheus:
          config:
            scrape_configs:
              # Collector self-metrics
              - job_name: otel-collector-self
                scrape_interval: 30s
                static_configs:
                  - targets: ["0.0.0.0:8888"]

              # Kubernetes pod discovery via annotations
              - job_name: kubernetes-pods
                scrape_interval: 30s
                kubernetes_sd_configs:
                  - role: pod
                relabel_configs:
                  # Only scrape pods with prometheus.io/scrape: "true"
                  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                    action: keep
                    regex: "true"
                  # Respect custom metrics path annotation
                  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
                    action: replace
                    target_label: __metrics_path__
                    regex: (.+)
                  # Respect custom port annotation
                  - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
                    action: replace
                    regex: "([^:]+)(?::\\d+)?;(\\d+)"
                    replacement: "$1:$2"
                    target_label: __address__
                  # Carry namespace and pod name as labels
                  - source_labels: [__meta_kubernetes_namespace]
                    target_label: namespace
                  - source_labels: [__meta_kubernetes_pod_name]
                    target_label: pod
                  - source_labels: [__meta_kubernetes_pod_label_app]
                    target_label: app

      processors:
        # ── Memory Limiter ──────────────────────────────────────────────────
        # MUST be the first processor in every pipeline.
        # Refuses new data when memory exceeds limit_mib to avoid OOM kills.
        memory_limiter:
          check_interval: 5s
          limit_mib: ${var.otel_collector_memory_limit_mib}
          spike_limit_mib: 128

        # ── Batch ───────────────────────────────────────────────────────────
        # Accumulates spans/metrics/logs into batches before export.
        # Reduces network round-trips and improves throughput.
        batch:
          timeout: 5s
          send_batch_size: 1000
          send_batch_max_size: 2000

      exporters:
        # ── Prometheus Exporter ─────────────────────────────────────────────
        # Exposes all received + scraped metrics on :8889 in Prometheus format.
        # Add a ServiceMonitor or scrape config pointing at this endpoint to
        # pull OTel-originated metrics into kube-prometheus-stack.
        prometheus:
          endpoint: "0.0.0.0:8889"
          namespace: "otel"

        # ── Debug Exporter ──────────────────────────────────────────────────
        # Logs a one-line summary of each batch — useful for verifying the
        # pipeline is receiving data without flooding logs.
        debug:
          verbosity: basic

      service:
        # Telemetry config for the collector itself.
        telemetry:
          logs:
            level: info
          metrics:
            address: "0.0.0.0:8888"

        pipelines:
          # Metrics: receive via OTLP and by scraping, export to Prometheus.
          metrics:
            receivers: [otlp, prometheus]
            processors: [memory_limiter, batch]
            exporters: [prometheus, debug]

          # Traces: receive via OTLP, log summaries.
          # Add an OTLP exporter here to forward to Jaeger/Tempo when ready.
          traces:
            receivers: [otlp]
            processors: [memory_limiter, batch]
            exporters: [debug]

          # Logs: receive via OTLP, log summaries.
          # Add a Loki exporter here to ship structured logs to Loki.
          logs:
            receivers: [otlp]
            processors: [memory_limiter, batch]
            exporters: [debug]
    YAML
  ]
}
