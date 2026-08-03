resource "azurerm_user_assigned_identity" "deployer" {
  name                = local.deployer_identity_name
  location            = data.azurerm_resource_group.shared.location
  resource_group_name = data.azurerm_resource_group.shared.name

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_federated_identity_credential" "github_production" {
  name                = "github-production"
  resource_group_name = data.azurerm_resource_group.shared.name
  parent_id           = azurerm_user_assigned_identity.deployer.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${local.github_owner}/${local.github_repository}:environment:${local.github_environment}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "deployer_cluster_user" {
  name               = local.deployer_role_name
  scope              = data.azurerm_kubernetes_cluster.shared.id
  role_definition_id = local.cluster_user_role_id
  principal_id       = azurerm_user_assigned_identity.deployer.principal_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_user_assigned_identity" "secrets" {
  name                = local.secret_identity_name
  location            = data.azurerm_resource_group.shared.location
  resource_group_name = data.azurerm_resource_group.shared.name

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_federated_identity_credential" "aks_workload" {
  name                = "aks-workload"
  resource_group_name = data.azurerm_resource_group.shared.name
  parent_id           = azurerm_user_assigned_identity.secrets.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.shared.oidc_issuer_url
  subject             = "system:serviceaccount:${local.namespace}:${local.service_account}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_key_vault" "pigeon" {
  name                       = local.key_vault_name
  location                   = data.azurerm_resource_group.shared.location
  resource_group_name        = data.azurerm_resource_group.shared.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "secret_identity_vault_access" {
  name               = local.secret_identity_role_name
  scope              = azurerm_key_vault.pigeon.id
  role_definition_id = local.secrets_user_role_id
  principal_id       = azurerm_user_assigned_identity.secrets.principal_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "operator_vault_access" {
  name               = local.operator_role_name
  scope              = azurerm_key_vault.pigeon.id
  role_definition_id = local.secrets_officer_role_id
  principal_id       = var.key_vault_admin_object_id

  lifecycle {
    prevent_destroy = true
  }
}
