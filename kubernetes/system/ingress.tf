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
      service:
        annotations:
          # Required for Azure load balancer to start directing traffic
          # Otherwise, visiting the public IP address will hang
          # https://github.com/Azure/AKS/issues/2903
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
