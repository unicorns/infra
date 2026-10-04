locals {
  public_ingress_namespace = "public-ingress"
  public_ingress_gateway   = "public-traefik"
  public_request_timeout   = "180s"
  cloudflare_proxy_cidrs = [
    "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22",
    "103.31.4.0/22", "141.101.64.0/18", "108.162.192.0/18",
    "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22",
    "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
    "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
    "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32",
    "2405:b500::/32", "2405:8100::/32", "2a06:98c0::/29", "2c0f:f248::/32",
  ]
}

resource "kubernetes_namespace" "public_ingress" {
  metadata {
    name = local.public_ingress_namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }
}

resource "helm_release" "public_traefik" {
  name       = local.public_ingress_gateway
  namespace  = kubernetes_namespace.public_ingress.metadata[0].name
  chart      = "traefik"
  repository = "https://traefik.github.io/charts"
  version    = local.traefik_chart_version
  atomic     = true
  skip_crds  = true
  timeout    = 600

  values = [yamlencode({
    image        = { tag = local.traefik_image_tag }
    nodeSelector = { "kubernetes.azure.com/mode" = "system" }
    deployment   = { replicas = 1 }
    ingressClass = {
      enabled        = true
      isDefaultClass = false
      name           = "public"
    }
    providers = {
      kubernetesCRD     = { enabled = false }
      kubernetesGateway = { enabled = false }
      kubernetesIngress = {
        enabled            = true
        ingressClass       = "public"
        allowEmptyServices = false
        publishedService   = { enabled = true }
      }
    }
    additionalArguments = [
      "--serverstransport.forwardingtimeouts.responseheadertimeout=${local.public_request_timeout}",
    ]
    ports = {
      web = {
        asDefault        = true
        forwardedHeaders = { trustedIPs = local.cloudflare_proxy_cidrs }
        transport        = { respondingTimeouts = { readTimeout = local.public_request_timeout } }
      }
      websecure = {
        asDefault        = true
        http             = { tls = { enabled = true } }
        forwardedHeaders = { trustedIPs = local.cloudflare_proxy_cidrs }
        transport        = { respondingTimeouts = { readTimeout = local.public_request_timeout } }
      }
    }
    service      = { spec = { type = "ClusterIP" } }
    api          = { dashboard = false }
    ingressRoute = { dashboard = { enabled = false } }
    resources = {
      requests = { cpu = "20m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }
  })]
}
