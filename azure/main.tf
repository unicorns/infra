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

# Subscription ID is obtained from Azure portal: https://portal.azure.com/#@unicorn.onmicrosoft.com/resource/subscriptions/da091416-7245-487a-a165-deb1cb35397e/overview
variable subscription_id {
  type = string
}

# Manually-created app registration:
# https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/d3652031-0c86-43e4-9129-4e50111477aa/isMSAApp~/false
#
# Subscription Permissions (https://portal.azure.com/#@unicorn.onmicrosoft.com/resource/subscriptions/da091416-7245-487a-a165-deb1cb35397e/users):
# - Contributor 
#
# Instructions:
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret
variable app_client_id {
  type = string
}
variable app_tenant_id {
  type = string
}
# Manually generated here:
# https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/d3652031-0c86-43e4-9129-4e50111477aa/isMSAApp~/false
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

resource "azurerm_resource_group" "unicorns-aks1" {
  name = "unicorns-aks1-rg"
  location = "Sweden Central"
}

resource "azurerm_kubernetes_cluster" "unicorns-aks1" {
  name                = "unicorns-aks1"
  location            = azurerm_resource_group.unicorns-aks1.location
  resource_group_name = azurerm_resource_group.unicorns-aks1.name
  dns_prefix          = "unicorns-aks1"

  default_node_pool {
    name       = "default"
    node_count = 2
    # 2 vCPU, 4 GiB RAM. 8 GiB temp disk. 30 GiB cache. $378.43/year.
    vm_size    = "Standard_B2s"

    # vm_size    = "Standard_E2as_v4"
    
    # Reduce the OS disk size so that it can fit in VMs with
    # smaller cache or temporary disk sizes. The minimum is 30 GB.
    # https://learn.microsoft.com/en-us/azure/aks/cluster-configuration#use-ephemeral-os-on-existing-clusters
    os_disk_size_gb = 30
    os_disk_type = "Ephemeral"

    # Use temporary disk instead of the OS disk for emptyDir volumes.
    # https://github.com/hashicorp/terraform-provider-azurerm/issues/15449
    #
    # Requires the "Microsoft.ContainerService/KubeletDisk" preview feature:
    # https://github.com/Azure/AKS/issues/930
    # There is no option to enable this in the Azure portal: https://portal.azure.com/#@unicorn.onmicrosoft.com/resource/subscriptions/da091416-7245-487a-a165-deb1cb35397e/previewfeatures
    # However, we can hack it by intercepting the API call.
    # But Azure appears to have put in another requirement to ensure the kubelet disk is either on the OS disk or has 32 GiB of space. The error message is:
    # performing CreateOrUpdate: unexpected status 400 (400 Bad Request) with response: {
    #   "code": "VMTemporaryDiskTooSmall",
    #   "details": null,
    #   "message": "The virtual machine size Standard_B2s has a max temporary disk size of 8589934592 bytes, but the kubelet disk requires 32212254720 bytes. Use a VM size with larger temporary disk or use the OS disk for kubelet.",
    #   "subcode": ""
    # }
    # kubelet_disk_type = "Temporary"

    temporary_name_for_rotation = "tmprotdef" # required when changing vm_size or os_disk_type

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  auto_scaler_profile {
    # Support deleting nodes with system pods
    skip_nodes_with_system_pods = false
    # Support deleting nodes with local storage (emptyDir or localPath volumes)
    skip_nodes_with_local_storage = false
  }
}

locals {
  azure_hours_per_month = 730
}

resource "azurerm_kubernetes_cluster_node_pool" "spot1" {
  name = "spot1"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.unicorns-aks1.id
  # vm_size = "Standard_B2ats_v2" # 2vCPU, 1GiB RAM, does not support ephemeral OS disk. Appears to be unsupported in AKS due to low RAM (node does not start in node pool).
  # vm_size = "Standard_D2as_v5" # 2vCPU, 8GiB RAM, does not support ephemeral OS disk
  # vm_size = "Standard_D2a_v4" # 2vCPU, 8GiB RAM, 50 GiB temp disk, 0 GiB cache.
  # vm_size = "Standard_D2as_v4" # 2vCPU, 8GiB RAM, 16 GiB temp disk, 50 GiB cache.
  # vm_size = "Standard_D4as_v4" # 4vCPU, 16GiB RAM, 32 GiB temp disk, 100 GiB cache.
  vm_size = "Standard_D2ads_v5" # 2vCPU, 8GiB RAM, 75 GiB temp disk, 0 GiB cache. Spot price $115.63/year in Sweden Central.
  # vm_size = "Standard_E2as_v5" # Does not support ephemeral OS disk.
  # vm_size = "Standard_B4ms" # 4vCPU, 16GiB RAM, 32 GiB temp disk, 0 GiB cache.

  os_disk_size_gb = 75
  os_disk_type = "Ephemeral"
  # kubelet_disk_type = "Temporary" # use the temp disk for emptyDir volumes. Otherwise, use the OS disk.

  priority = "Spot"
  eviction_policy = "Delete"
  spot_max_price = format("%.5f", 115.63	 / 12 / local.azure_hours_per_month) # max price per hour. Rounding because the provider only accepts 5 decimal places.
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule", # required for spot nodes. 
  ]

  enable_auto_scaling = true
  min_count = 0
  max_count = 3
}

output "kubernetes_cluster_name" {
  value = azurerm_kubernetes_cluster.unicorns-aks1.name
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.unicorns-aks1.kube_config_raw
  sensitive = true
}