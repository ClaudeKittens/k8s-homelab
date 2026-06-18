output "grafana_port_forward_command" {
  value       = "kubectl --kubeconfig=${pathexpand(var.kubeconfig_path)} -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
  description = "Run this in a terminal to access Grafana at http://localhost:3000"
}

output "grafana_credentials" {
  value       = "username: admin  |  password: (set via var.grafana_admin_password, default: homelab-admin)"
  description = "Grafana login credentials."
}

output "prometheus_port_forward_command" {
  value       = "kubectl --kubeconfig=${pathexpand(var.kubeconfig_path)} -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
  description = "Run this to access the Prometheus UI directly at http://localhost:9090"
}

output "alertmanager_port_forward_command" {
  value       = "kubectl --kubeconfig=${pathexpand(var.kubeconfig_path)} -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093"
  description = "Run this to access Alertmanager at http://localhost:9093"
}

output "otel_collector_otlp_grpc" {
  value       = "127.0.0.1:4317 (after: kubectl --kubeconfig=${pathexpand(var.kubeconfig_path)} -n opentelemetry port-forward svc/otel-collector-opentelemetry-collector 4317:4317)"
  description = "OTLP gRPC endpoint for sending traces/metrics/logs to the OTel Collector."
}

output "otel_collector_otlp_http" {
  value       = "http://127.0.0.1:4318 (after port-forwarding port 4318)"
  description = "OTLP HTTP endpoint for sending traces/metrics/logs to the OTel Collector."
}

output "loki_port_forward_command" {
  value       = "kubectl --kubeconfig=${pathexpand(var.kubeconfig_path)} -n logging port-forward svc/loki 3100:3100"
  description = "Run this to query Loki directly at http://localhost:3100"
}
