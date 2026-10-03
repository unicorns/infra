provider "cloudflare" {}

locals {
  gateway_ips = flatten([
    for status in kubernetes_service_v1.gateway.status : [
      for load_balancer in status.load_balancer : [
        for ingress in load_balancer.ingress : ingress.ip if ingress.ip != ""
      ]
    ]
  ])
}

resource "cloudflare_dns_record" "private_wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*.${local.domain}"
  type    = "A"
  content = one(local.gateway_ips)
  ttl     = 60
  proxied = false
  comment = "Private Kubernetes ingress over Tailscale"

  lifecycle {
    prevent_destroy = true

    precondition {
      condition = length(local.gateway_ips) == 1 && alltrue([
        for ip in local.gateway_ips : can(cidrhost("${ip}/10", 0)) ? cidrhost("${ip}/10", 0) == "100.64.0.0" : false
      ])
      error_message = "The private gateway must publish exactly one Tailscale IPv4 address in 100.64.0.0/10."
    }
  }
}
