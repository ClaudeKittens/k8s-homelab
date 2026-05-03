terraform {
  required_version = ">= 1.7.0"

  required_providers {
    # null_resource is used to run shell commands via local-exec / remote-exec.
    # All k3s installation logic runs through limactl shell (local-exec).
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    # local provider writes the kubeconfig to disk after it is copied from the VM.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
