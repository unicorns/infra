data "cloudflare_zone" "primary" {
  count = local.pigeon_dns_enabled ? 1 : 0

  name = local.cloudflare_zone_name
}

resource "cloudflare_record" "pigeon" {
  count = local.pigeon_dns_enabled ? 1 : 0

  zone_id = data.cloudflare_zone.primary[0].id
  name    = local.hostname
  type    = "A"
  content = data.azurerm_public_ip.ingress.ip_address
  proxied = true
  ttl     = 1
  comment = "Managed by Terraform"

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [terraform_data.github_deployment_policies_are_exclusive]
}

data "azurerm_public_ip" "ingress" {
  name                = "unicorns-aks-ingress-ip"
  resource_group_name = data.azurerm_kubernetes_cluster.shared.node_resource_group
}
