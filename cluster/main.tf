# ── Provider Configuration ────────────────────────────────────────────────────
#
# Both providers read the same kubeconfig that the bootstrap module wrote.
# pathexpand() resolves "~" so the path works regardless of how the variable
# is passed in.

provider "helm" {
  kubernetes {
    config_path = pathexpand(var.kubeconfig_path)
  }
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}
