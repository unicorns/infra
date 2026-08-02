resource "azurerm_kubernetes_cluster" "shared" {
  name                = local.aks_name
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  dns_prefix          = local.aks_name
  kubernetes_version  = var.aks_kubernetes_version
  sku_tier            = "Free"

  default_node_pool {
    name                 = "system"
    node_count           = 1
    orchestrator_version = var.aks_kubernetes_version
    vm_size              = var.aks_system_vm_size
    max_pods             = 30

    # Keep the system pool cheap and predictable. B2s cannot use AKS temporary
    # kubelet disk because its temp disk is too small, so use the managed OS disk.
    os_disk_size_gb   = 32
    os_disk_type      = "Managed"
    kubelet_disk_type = "OS"

    temporary_name_for_rotation = "tmpsystem"

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 10
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.shared.id
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  auto_scaler_profile {
    skip_nodes_with_local_storage = false
    skip_nodes_with_system_pods   = false
  }

  node_os_upgrade_channel           = "NodeImage"
  oidc_issuer_enabled               = true
  role_based_access_control_enabled = true
  workload_identity_enabled         = true

  maintenance_window_node_os {
    utc_offset  = "+00:00"
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "09:00"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  count = var.enable_spot_node_pool ? 1 : 0

  name                  = "appspot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.shared.id
  orchestrator_version  = var.aks_kubernetes_version
  vm_size               = var.aks_spot_vm_size
  max_pods              = 30

  os_disk_size_gb   = 32
  os_disk_type      = "Managed"
  kubelet_disk_type = "OS"

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = var.aks_spot_max_price
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule",
  ]

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = 2
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.shared.name
}

output "aks_resource_group_name" {
  value = azurerm_resource_group.shared.name
}

output "aks_kube_config" {
  value     = azurerm_kubernetes_cluster.shared.kube_config_raw
  sensitive = true
}

output "aks_key_vault_secret_provider_client_id" {
  value = azurerm_kubernetes_cluster.shared.key_vault_secrets_provider[0].secret_identity[0].client_id
}

output "aks_key_vault_secret_provider_object_id" {
  value = azurerm_kubernetes_cluster.shared.key_vault_secrets_provider[0].secret_identity[0].object_id
}
