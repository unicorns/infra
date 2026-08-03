terraform {
  cloud {
    organization = "unicornsftw"

    workspaces {
      name = "unicorns-azure"
    }
  }

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.11.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.25.0"
    }
  }
}

variable "subscription_id" {
  type    = string
  default = null
}

variable "app_client_id" {
  type    = string
  default = null
}
variable "app_tenant_id" {
  type    = string
  default = null
}
variable "app_client_secret" {
  type      = string
  sensitive = true
  default   = null
}

variable "location" {
  type    = string
  default = "West US 3"
}

variable "name_prefix" {
  type    = string
  default = "unicorns"
}

variable "aks_kubernetes_version" {
  type    = string
  default = "1.34.8"
}

variable "aks_system_vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "aks_admin_group_object_ids" {
  type        = set(string)
  description = "Microsoft Entra group object IDs that administer the AKS cluster"

  validation {
    condition     = length(var.aks_admin_group_object_ids) > 0
    error_message = "At least one AKS administrator group object ID is required."
  }
}

variable "enable_spot_node_pool" {
  type    = bool
  default = true
}

variable "aks_spot_vm_size" {
  type    = string
  default = "Standard_D2ps_v6"
}

variable "aks_spot_max_price" {
  type    = number
  default = 0.02
}

variable "log_analytics_daily_quota_gb" {
  type    = number
  default = 0.25
}

variable "key_vault_name" {
  type    = string
  default = "unicornsftw-kv"
}

variable "key_vault_admin_object_ids" {
  type    = set(string)
  default = []
}

# Auth guide
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret
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

provider "azapi" {
  subscription_id = var.subscription_id
  client_id       = var.app_client_id
  tenant_id       = var.app_tenant_id
  client_secret   = var.app_client_secret

  enable_preflight = true
}

data "azurerm_client_config" "current" {}

locals {
  aks_name            = "${var.name_prefix}-aks"
  resource_group_name = "${local.aks_name}-rg"

  key_vault_admin_object_ids = toset(concat(
    [data.azurerm_client_config.current.object_id],
    tolist(var.key_vault_admin_object_ids),
  ))
}
