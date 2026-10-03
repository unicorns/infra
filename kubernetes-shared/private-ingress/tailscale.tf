resource "kubernetes_namespace" "tailscale" {
  metadata {
    name = "tailscale"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "helm_release" "tailscale" {
  name       = "tailscale-operator"
  namespace  = kubernetes_namespace.tailscale.metadata[0].name
  chart      = "tailscale-operator"
  repository = "https://pkgs.tailscale.com/helmcharts"
  version    = "1.102.4"
  atomic     = true

  values = [yamlencode({
    oauth = {
      clientId = var.tailscale_client_id
      audience = var.tailscale_audience
    }
    ingressClass = { enabled = false }
    operatorConfig = {
      hostname    = "unicorns-aks-operator"
      defaultTags = [local.operator_tag]
      nodeSelector = {
        "kubernetes.io/os"          = "linux"
        "kubernetes.azure.com/mode" = "system"
      }
      resources = {
        requests = { cpu = "20m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }
    proxyConfig = { defaultTags = local.proxy_tag }
  })]
}

resource "kubectl_manifest" "tailscale_proxy_class" {
  yaml_body = yamlencode({
    apiVersion = "tailscale.com/v1alpha1"
    kind       = "ProxyClass"
    metadata   = { name = local.proxy_group }
    spec = {
      statefulSet = {
        pod = {
          nodeSelector = { "kubernetes.azure.com/mode" = "system" }
          tailscaleContainer = {
            resources = {
              requests = { cpu = "20m", memory = "64Mi" }
              limits   = { memory = "256Mi" }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.tailscale]
}

resource "kubectl_manifest" "tailscale_proxy_group" {
  yaml_body = yamlencode({
    apiVersion = "tailscale.com/v1alpha1"
    kind       = "ProxyGroup"
    metadata   = { name = local.proxy_group }
    spec = {
      type       = "ingress"
      replicas   = 1
      proxyClass = local.proxy_group
      tags       = [local.proxy_tag]
    }
  })

  depends_on = [kubectl_manifest.tailscale_proxy_class]
}
