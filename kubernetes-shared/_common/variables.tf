variable "kubernetes_cluster_name" {
  type        = string
  description = "The AKS cluster name"
}

variable "key_vault_name" {
  type        = string
  description = "The Azure Key Vault name"
}

variable "key_vault_tenant_id" {
  type        = string
  description = "The Azure tenant ID for Key Vault"
}

variable "key_vault_secret_provider_client_id" {
  type        = string
  description = "The user-assigned client ID created by the AKS Key Vault CSI add-on"
}

variable "ingress_external_ip" {
  type        = string
  description = "Static public IP assigned to the shared ingress controller"
  default     = null
}
