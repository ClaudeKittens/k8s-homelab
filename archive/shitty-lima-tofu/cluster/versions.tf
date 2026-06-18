terraform {
  required_version = ">= 1.7.0"

  required_providers {
    # Helm provider manages all Kubernetes workloads via Helm charts.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }

    # Kubernetes provider is used for namespace creation and any raw manifests
    # that don't have a Helm chart (none currently, but good to have).
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
  }
}
