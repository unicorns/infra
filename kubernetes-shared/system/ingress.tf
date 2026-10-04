data "kubernetes_service" "public_ingress" {
  metadata {
    name      = helm_release.public_traefik.name
    namespace = helm_release.public_traefik.namespace
  }
}

output "ingress_external_ip" {
  value = data.kubernetes_service.public_ingress.status[0].load_balancer[0].ingress[0].ip
}
