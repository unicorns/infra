resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  version    = "v4.9.0"

  values = [<<EOF
    controller:
      replicaCount: 1
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 250m
          memory: 384Mi
      service:
%{if var.ingress_external_ip != null}
        loadBalancerIP: ${var.ingress_external_ip}
%{endif}
        annotations:
          # Required for Azure load balancer to start directing traffic.
          service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
      metrics:
        enabled: true
  EOF
  ]
}

data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "${helm_release.ingress_nginx.name}-controller"
    namespace = kubernetes_namespace.ingress_nginx.metadata[0].name
  }
}

output "ingress_external_ip" {
  value = data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip
}
