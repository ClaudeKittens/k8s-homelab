output "kubeconfig_path" {
  value       = local.kubeconfig_path
  description = "Absolute path to the kubeconfig written to the Mac host. Pass this to the cluster module."
}

output "kubectl_test_command" {
  value       = "kubectl --kubeconfig=${local.kubeconfig_path} get nodes"
  description = "Run this to verify cluster connectivity after bootstrap."
}

output "cluster_module_apply_command" {
  value       = "tofu -chdir=../cluster apply -var=\"kubeconfig_path=${local.kubeconfig_path}\""
  description = "Convenience command to apply the cluster module with the correct kubeconfig."
}
