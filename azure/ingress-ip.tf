resource "azurerm_public_ip" "ingress" {
  name                = "${local.aks_name}-ingress-ip"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_kubernetes_cluster.shared.node_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
}

output "aks_node_resource_group_name" {
  value = azurerm_kubernetes_cluster.shared.node_resource_group
}

output "ingress_static_ip" {
  value = azurerm_public_ip.ingress.ip_address
}

output "ingress_static_ip_name" {
  value = azurerm_public_ip.ingress.name
}
