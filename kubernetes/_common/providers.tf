terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.25.2"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "2.0.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.8.0"
    }
  }
}

variable "kube_config_path" {
  type = string
  description = "The path to the kubeconfig file"
}

provider "kubernetes" {
  config_path = var.kube_config_path
}

provider "kubectl" {
  config_path = var.kube_config_path
}

provider "helm" {
  kubernetes {
    config_path = var.kube_config_path
  }
}
