resource "azurerm_resource_group" "unicorns-aks1" {
  name = "unicorns-aks1-rg"
  location = "Sweden Central"
}

locals {
  aks1_kubernetes_version = "1.30.3"
}

resource "azurerm_kubernetes_cluster" "unicorns-aks1" {
  name                = "unicorns-aks1"
  location            = azurerm_resource_group.unicorns-aks1.location
  resource_group_name = azurerm_resource_group.unicorns-aks1.name
  dns_prefix          = "unicorns-aks1"

  kubernetes_version = local.aks1_kubernetes_version

  default_node_pool {
    name       = "default"
    node_count = 1

    orchestrator_version = local.aks1_kubernetes_version

    # The maximum number of pods affects memory reservation in AKS 1.29 or later.
    # https://learn.microsoft.com/en-us/azure/aks/node-resource-reservations#memory-reservations
    max_pods = 30

    # 2 vCPU, 4 GiB RAM. 8 GiB temp disk. 30 GiB cache. $378.43/year.
    # vm_size    = "Standard_B2s"
    # 2 vCPU, 8 GiB RAM. No temp disk. Does not support ephemeral OS disk. $602.69/year.
    vm_size    = "Standard_B2ps_v2"
    # 2 vCPU, 8 GiB RAM. 16 GiB temp disk. 30 GiB cache. $756.86/year.
    # vm_size    = "Standard_B2ms"

    # vm_size    = "Standard_E2as_v4"
    
    # Reduce the OS disk size so that it can fit in VMs with
    # smaller cache or temporary disk sizes. The minimum is 30 GB.
    # https://learn.microsoft.com/en-us/azure/aks/cluster-configuration#use-ephemeral-os-on-existing-clusters
    # os_disk_size_gb = 30
    # os_disk_type = "Ephemeral"
    # For VMs that don't support ephemeral OS disk, use managed disk.
    # The OS disks are placed on "Premium SSD" storage:
    # https://learn.microsoft.com/en-us/azure/aks/concepts-clusters-workloads#default-os-disk-sizing
    # Pricing:
    # https://azure.microsoft.com/en-ca/pricing/details/managed-disks/
    os_disk_size_gb = 32
    os_disk_type = "Managed"

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
      drain_timeout_in_minutes = 30
      node_soak_duration_in_minutes = 0
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

  node_os_upgrade_channel = "NodeImage"
  maintenance_window_node_os {
    utc_offset = "+00:00"

    frequency = "Weekly"
    interval = 1
    duration = 4 # hours
    day_of_week = "Sunday"

    start_time = "09:00" # UTC. This is 2 AM PDT or 1 AM PST.
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "aks1spot1" {
  name = "aks1spot1"
  
  orchestrator_version = local.aks1_kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.unicorns-aks1.id
  # vm_size = "Standard_B2ats_v2" # 2vCPU, 1GiB RAM, does not support ephemeral OS disk. Appears to be unsupported in AKS due to low RAM (node does not start in node pool).
  # vm_size = "Standard_D2as_v5" # 2vCPU, 8GiB RAM, does not support ephemeral OS disk
  # vm_size = "Standard_D2a_v4" # 2vCPU, 8GiB RAM, 50 GiB temp disk, 0 GiB cache.
  # vm_size = "Standard_D2as_v4" # 2vCPU, 8GiB RAM, 16 GiB temp disk, 50 GiB cache.
  # vm_size = "Standard_D4as_v4" # 4vCPU, 16GiB RAM, 32 GiB temp disk, 100 GiB cache.
  # vm_size = "Standard_D2ads_v5" # 2vCPU, 8GiB RAM, 75 GiB temp disk, 0 GiB cache. Spot price $115.63/year in Sweden Central.
  # vm_size = "Standard_E2as_v5" # Does not support ephemeral OS disk.
  # vm_size = "Standard_B4ms" # 4vCPU, 16GiB RAM, 32 GiB temp disk, 0 GiB cache.
  vm_size = "Standard_D2pds_v5" # 2vCPU, 8GiB RAM, 75 GiB temp disk, 50 GiB cache. Spot price $117.73/year in Sweden Central.
  # vm_size = "Standard_E2pds_v5" # 2vCPU, 16GiB RAM, 75 GiB temp disk, 50 GiB cache. Does not support spot VMs
  # vm_size = "Standard_E2ps_v5" # 2vCPU, 16GiB RAM, no temp disk, 50 GiB cache. Doesn't support ephemeral OS disk. Spot price $93.732/year in Sweden Central.
  # vm_size = "Standard_E2a_v4" # 2vCPU, 16GiB RAM, 50 GiB temp disk, no cache. Spot price $117.47/year in Sweden Central.
  # vm_size = "Standard_E2as_v4" # 2vCPU, 16GiB RAM, 32 GiB temp disk, 50 GiB cache. Spot price $117.47/year in Sweden Central.

  os_disk_size_gb = 50
  os_disk_type = "Ephemeral"
  kubelet_disk_type = "Temporary" # use the temp disk for emptyDir volumes. If not set, use the OS disk.
  max_pods = 30

  priority = "Spot"
  eviction_policy = "Delete"
  spot_max_price = format("%.5f", (117.73 * local.annual_spot_cost_multiplier) / 12 / local.azure_hours_per_month) # max price per hour. Rounding because the provider only accepts 5 decimal places.
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule", # required for spot nodes. 
  ]

  auto_scaling_enabled = true
  min_count = 0
  max_count = 2

  lifecycle {
    ignore_changes = [
      # Ignore changes because changing this requires recreating the node pool.
      spot_max_price
    ]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "aks1spot4" {
  name = "aks1spot4"

  orchestrator_version = local.aks1_kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.unicorns-aks1.id
  # vm_size = "Standard_B2ats_v2" # 2vCPU, 1GiB RAM, does not support ephemeral OS disk. Appears to be unsupported in AKS due to low RAM (node does not start in node pool).
  # vm_size = "Standard_D2as_v5" # 2vCPU, 8GiB RAM, does not support ephemeral OS disk
  # vm_size = "Standard_D2a_v4" # 2vCPU, 8GiB RAM, 50 GiB temp disk, 0 GiB cache.
  # vm_size = "Standard_D2as_v4" # 2vCPU, 8GiB RAM, 16 GiB temp disk, 50 GiB cache.
  # vm_size = "Standard_D4as_v4" # 4vCPU, 16GiB RAM, 32 GiB temp disk, 100 GiB cache.
  # vm_size = "Standard_D2ads_v5" # 2vCPU, 8GiB RAM, 75 GiB temp disk, 0 GiB cache. Spot price $115.63/year in Sweden Central.
  # vm_size = "Standard_E2as_v5" # Does not support ephemeral OS disk.
  # vm_size = "Standard_B4ms" # 4vCPU, 16GiB RAM, 32 GiB temp disk, 0 GiB cache.
  # vm_size = "Standard_D2pds_v5" # 2vCPU, 8GiB RAM, 75 GiB temp disk, 50 GiB cache. Spot price $84.096/year in Sweden Central.
  # vm_size = "Standard_E2pds_v5" # 2vCPU, 16GiB RAM, 75 GiB temp disk, 50 GiB cache. Does not support spot VMs
  # vm_size = "Standard_E2ps_v5" # 2vCPU, 16GiB RAM, no temp disk, 50 GiB cache. Doesn't support ephemeral OS disk. Spot price $93.732/year in Sweden Central.
  # vm_size = "Standard_E2a_v4" # 2vCPU, 16GiB RAM, 50 GiB temp disk, no cache. Spot price $155.05/year in Sweden Central.
  vm_size = "Standard_E2as_v4" # 2vCPU, 16GiB RAM, 32 GiB temp disk, 50 GiB cache. Spot price $155.05/year in Sweden Central.

  os_disk_size_gb = 50 # minimum is 30.
  os_disk_type = "Ephemeral" # when using ephemeral OS disk, the disk will be placed in cache if there's room. If not, it will be placed in temp disk.
  kubelet_disk_type = "Temporary" # use the temp disk for emptyDir volumes. If not set, use the OS disk.
  max_pods = 60

  priority = "Spot"
  eviction_policy = "Delete"
  spot_max_price = format("%.5f", (155.05 * local.annual_spot_cost_multiplier) / 12 / local.azure_hours_per_month) # max price per hour. Rounding because the provider only accepts 5 decimal places.
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule", # required for spot nodes. 
  ]

  auto_scaling_enabled = true
  min_count = 0
  max_count = 2

  lifecycle {
    ignore_changes = [
      # Ignore changes because changing this requires recreating the node pool.
      spot_max_price
    ]
  }
}

output "aks1_cluster_name" {
  value = azurerm_kubernetes_cluster.unicorns-aks1.name
}

output "aks1_kube_config" {
  value     = azurerm_kubernetes_cluster.unicorns-aks1.kube_config_raw
  sensitive = true
}
