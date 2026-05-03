variable "kubeconfig_path" {
  type        = string
  description = <<-EOD
    Absolute path to the kubeconfig for the k3s cluster.
    Produced by the bootstrap module output "kubeconfig_path".
    Default matches the bootstrap module's default output location.
  EOD
  default     = "~/.kube/k3s-homelab.yaml"
}

variable "grafana_admin_password" {
  type        = string
  description = "Password for the Grafana 'admin' user. Change before any network exposure."
  sensitive   = true
  default     = "homelab-admin"
}

variable "grafana_persistence_size" {
  type        = string
  description = "PVC size for Grafana dashboards / plugins storage."
  default     = "5Gi"
}

variable "prometheus_retention" {
  type        = string
  description = "How long Prometheus retains metrics (e.g. '7d', '30d')."
  default     = "7d"
}

variable "prometheus_storage_size" {
  type        = string
  description = "PVC size for Prometheus TSDB."
  default     = "20Gi"
}

variable "loki_storage_size" {
  type        = string
  description = "PVC size for Loki log storage."
  default     = "20Gi"
}

variable "otel_collector_memory_limit_mib" {
  type        = number
  description = "Hard memory limit (MiB) for the OTel Collector container."
  default     = 512
}
