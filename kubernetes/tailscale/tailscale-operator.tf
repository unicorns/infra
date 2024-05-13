resource "kubernetes_namespace" "tailscale" {
  metadata {
    name = "tailscale"
  }
}

variable "tailscale_operator_client_id" {
  type = string
}

variable "tailscale_operator_client_secret" {
  type = string
  sensitive = true
}

resource "kubernetes_secret" "tailscale_operator_oauth" {
  metadata {
    name      = "operator-oauth"
    namespace = kubernetes_namespace.tailscale.metadata[0].name
  }
  data = {
    "client_id"     = var.tailscale_operator_client_id
    "client_secret" = var.tailscale_operator_client_secret
  }
}

resource "helm_release" "tailscale" {
  name             = "tailscale-operator"
  namespace        = kubernetes_namespace.tailscale.metadata[0].name
  chart            = "tailscale-operator"
  repository       = "https://pkgs.tailscale.com/helmcharts"

  depends_on = [ kubernetes_secret.tailscale_operator_oauth ]

  values = [<<EOF
    operatorConfig:
      hostname: "${var.kubernetes_cluster_name}-tailscale-operator"
  EOF
  ]
}

resource "kubernetes_manifest" "tailscale-exit-node" {
  manifest = {
    "apiVersion" = "tailscale.com/v1alpha1"
    "kind" = "Connector"
    "metadata" = {
      "name" = "tailscale-exit-node"
    }
    "spec" = {
      "hostname" = "${var.kubernetes_cluster_name}-exit-node"
      "exitNode" = true
    }
  }

  depends_on = [ helm_release.tailscale ]
}
