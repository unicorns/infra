terraform {
  cloud {
    organization = "unicornsftw"

    workspaces {
      name = "unicorns-azure"
    }
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.103.1"
    }
  }
}

variable subscription_id {
  type = string
}

variable app_client_id {
  type = string
}
variable app_tenant_id {
  type = string
}
variable app_client_secret {
  type = string
  sensitive = true
}

# Auth guide
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id     = var.app_client_id
  tenant_id     = var.app_tenant_id
  client_secret = var.app_client_secret
}
