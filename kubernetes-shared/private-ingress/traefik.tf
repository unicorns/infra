resource "kubernetes_persistent_volume_claim" "acme" {
  metadata {
    name      = local.acme_claim
    namespace = local.namespace
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "managed-csi"
    resources {
      requests = { storage = "1Gi" }
    }
  }

  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "helm_release" "traefik" {
  name       = local.gateway
  namespace  = local.namespace
  chart      = "traefik"
  repository = "https://traefik.github.io/charts"
  version    = local.traefik_chart_version
  atomic     = true

  values = [yamlencode({
    nodeSelector = { "kubernetes.azure.com/mode" = "system" }
    image        = { tag = local.traefik_image_tag }
    deployment = {
      replicas = 1
      annotations = {
        "secret.reloader.stakater.com/reload" = local.cloudflare_secret
      }
      initContainers = [{
        name         = "acme-storage-permissions"
        image        = "docker.io/traefik:${local.traefik_image_tag}"
        command      = ["/bin/sh", "-ec", "umask 077; touch /data/acme.json; chmod 600 /data/acme.json"]
        volumeMounts = [{ name = "data", mountPath = "/data" }]
        securityContext = {
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
          readOnlyRootFilesystem   = true
        }
        resources = {
          requests = { cpu = "10m", memory = "16Mi" }
          limits   = { memory = "32Mi" }
        }
      }]
    }
    updateStrategy = { type = "Recreate" }
    podSecurityContext = {
      fsGroup             = 65532
      fsGroupChangePolicy = "OnRootMismatch"
    }
    persistence = {
      enabled       = true
      existingClaim = local.acme_claim
    }
    env = [{
      name = "CF_DNS_API_TOKEN"
      valueFrom = {
        secretKeyRef = { name = local.cloudflare_secret, key = "api-token" }
      }
    }]
    certificatesResolvers = {
      cloudflare = {
        acme = {
          email        = var.acme_email
          storage      = "/data/acme.json"
          dnsChallenge = { provider = "cloudflare" }
        }
      }
    }
    ingressClass = {
      enabled        = true
      isDefaultClass = false
      name           = local.ingress_class
    }
    providers = {
      kubernetesCRD = {
        enabled                      = true
        namespaces                   = [local.namespace]
        defaultTLSResourcesNamespace = local.namespace
        safeNaming                   = true
        allowEmptyServices           = false
      }
      kubernetesIngress = {
        enabled            = true
        ingressClass       = local.ingress_class
        allowEmptyServices = false
        publishedService = {
          enabled      = true
          pathOverride = "${local.namespace}/${local.gateway}"
        }
      }
      kubernetesGateway = { enabled = false }
    }
    ports = {
      web = { expose = { default = false } }
      websecure = {
        asDefault = true
        expose    = { default = true }
        http = {
          tls = {
            enabled      = true
            certResolver = "cloudflare"
            domains      = [{ main = "*.${local.domain}" }]
          }
        }
      }
    }
    service = { enabled = false }
    tlsOptions = {
      default = { minVersion = "VersionTLS12", sniStrict = true }
    }
    api          = { dashboard = false }
    ingressRoute = { dashboard = { enabled = false } }
    resources = {
      requests = { cpu = "20m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }
  })]

  depends_on = [kubernetes_persistent_volume_claim.acme, kubectl_manifest.tailscale_proxy_group]
}

resource "kubernetes_service_v1" "gateway" {
  metadata {
    name      = local.gateway
    namespace = local.namespace
    annotations = {
      "tailscale.com/hostname"    = local.proxy_group
      "tailscale.com/proxy-group" = local.proxy_group
    }
  }

  spec {
    type                              = "LoadBalancer"
    load_balancer_class               = "tailscale"
    allocate_load_balancer_node_ports = false
    selector = {
      "app.kubernetes.io/name"     = "traefik"
      "app.kubernetes.io/instance" = "${local.gateway}-${local.namespace}"
    }
    port {
      name        = "websecure"
      protocol    = "TCP"
      port        = 443
      target_port = "websecure"
    }
  }

  wait_for_load_balancer = true

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [helm_release.traefik]
}
