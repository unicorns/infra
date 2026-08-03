terraform {
  required_version = ">= 1.8.0"

  cloud {
    organization = "unicornsftw"

    workspaces {
      name = "unicorns-application-pigeon-registration"
    }
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.25.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.52.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.25.2"
    }
  }
}

variable "subscription_id" {
  type = string
}

variable "app_client_id" {
  type = string
}

variable "app_tenant_id" {
  type = string
}

variable "app_client_secret" {
  type      = string
  sensitive = true
}

variable "kube_config_path" {
  type = string
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "key_vault_admin_object_id" {
  type        = string
  description = "Microsoft Entra object ID that administers Pigeon runtime secrets"
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }

  subscription_id = var.subscription_id
  client_id       = var.app_client_id
  tenant_id       = var.app_tenant_id
  client_secret   = var.app_client_secret
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "github" {
  owner = local.github_owner
  token = var.github_token
}

provider "kubernetes" {
  config_path = var.kube_config_path
}

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "shared" {
  name = local.resource_group_name
}

data "azurerm_kubernetes_cluster" "shared" {
  name                = local.aks_cluster_name
  resource_group_name = data.azurerm_resource_group.shared.name
}

locals {
  namespace              = "pigeon"
  service_account        = "pigeon"
  resource_group_name    = "unicorns-aks-rg"
  aks_cluster_name       = "unicorns-aks"
  key_vault_name         = "pigeonmqq3vzwotb2qo"
  deployer_identity_name = "pigeon-deployer"
  secret_identity_name   = "pigeon-secrets"
  github_owner           = "ben-z"
  github_repository      = "pigeon"
  github_environment     = "production"
  hostname               = "pigeon.benzhang.dev"
  cloudflare_zone_name   = "benzhang.dev"
  pigeon_url             = "https://${local.hostname}"
  # Activate in a separate reviewed change after the workload is ready.
  pigeon_dns_enabled        = false
  resource_group_id         = "/subscriptions/${var.subscription_id}/resourceGroups/${local.resource_group_name}"
  aks_id                    = "${local.resource_group_id}/providers/Microsoft.ContainerService/managedClusters/${local.aks_cluster_name}"
  key_vault_id              = "${local.resource_group_id}/providers/Microsoft.KeyVault/vaults/${local.key_vault_name}"
  deployer_identity_id      = "${local.resource_group_id}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${local.deployer_identity_name}"
  secret_identity_id        = "${local.resource_group_id}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${local.secret_identity_name}"
  cluster_user_role_id      = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4abbcc35-e782-43d8-92c5-2d3f1bd2253f"
  secrets_officer_role_id   = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
  secrets_user_role_id      = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
  deployer_role_name        = "119e743b-0718-5e56-a7e9-4a30bb9841d8"
  secret_identity_role_name = "83c96395-0289-56d4-a0da-d2dc8a790f9e"
  operator_role_name        = "18a5464a-df90-5e73-9a04-79e922cf796e"

  github_environment_variables = {
    AZURE_AKS_CLUSTER_NAME           = local.aks_cluster_name
    AZURE_CLIENT_ID                  = azurerm_user_assigned_identity.deployer.client_id
    AZURE_RESOURCE_GROUP             = local.resource_group_name
    AZURE_SUBSCRIPTION_ID            = var.subscription_id
    AZURE_TENANT_ID                  = data.azurerm_client_config.current.tenant_id
    PIGEON_KEY_VAULT_NAME            = azurerm_key_vault.pigeon.name
    PIGEON_SECRET_IDENTITY_CLIENT_ID = azurerm_user_assigned_identity.secrets.client_id
    PIGEON_URL                       = local.pigeon_url
  }
}
