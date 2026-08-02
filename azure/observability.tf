resource "azurerm_resource_group" "shared" {
  name     = local.resource_group_name
  location = var.location
}

resource "azurerm_log_analytics_workspace" "shared" {
  name                = "${local.aks_name}-logs"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.log_analytics_daily_quota_gb
}

output "resource_group_name" {
  value = azurerm_resource_group.shared.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.shared.id
}

output "log_analytics_daily_quota_gb" {
  value = azurerm_log_analytics_workspace.shared.daily_quota_gb
}
