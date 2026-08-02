resource "azurerm_key_vault" "shared" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  dynamic "access_policy" {
    for_each = local.key_vault_admin_object_ids

    content {
      tenant_id = data.azurerm_client_config.current.tenant_id
      object_id = access_policy.value

      secret_permissions = [
        "Backup",
        "Delete",
        "Get",
        "List",
        "Purge",
        "Recover",
        "Restore",
        "Set",
      ]
    }
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_kubernetes_cluster.shared.key_vault_secrets_provider[0].secret_identity[0].object_id

    secret_permissions = [
      "Get",
      "List",
    ]
  }
}

output "key_vault_name" {
  value = azurerm_key_vault.shared.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.shared.vault_uri
}

output "key_vault_tenant_id" {
  value = azurerm_key_vault.shared.tenant_id
}
