variable "lima_vm_name" {
  type        = string
  description = "Name given to the Lima VM at start time (limactl start --name=<name>)"
  default     = "k8s-homelab"
}

variable "k3s_version" {
  type        = string
  description = <<-EOD
    k3s release tag to install.
    Find the latest stable release at https://github.com/k3s-io/k3s/releases
    Example: "v1.30.3+k3s1"
  EOD
  default     = "v1.30.3+k3s1"
}

variable "kubeconfig_dir" {
  type        = string
  description = "Host directory to write the generated kubeconfig into. Tilde is expanded."
  default     = "~/.kube"
}
