import {
  to = azurerm_user_assigned_identity.deployer
  id = local.deployer_identity_id
}

import {
  to = azurerm_federated_identity_credential.github_production
  id = "${local.deployer_identity_id}/federatedIdentityCredentials/github-production"
}

import {
  to = azurerm_role_assignment.deployer_cluster_user
  id = "${local.aks_id}/providers/Microsoft.Authorization/roleAssignments/${local.deployer_role_name}"
}

import {
  to = azurerm_user_assigned_identity.secrets
  id = local.secret_identity_id
}

import {
  to = azurerm_federated_identity_credential.aks_workload
  id = "${local.secret_identity_id}/federatedIdentityCredentials/aks-workload"
}

import {
  to = azurerm_key_vault.pigeon
  id = local.key_vault_id
}

import {
  to = azurerm_role_assignment.secret_identity_vault_access
  id = "${local.key_vault_id}/providers/Microsoft.Authorization/roleAssignments/${local.secret_identity_role_name}"
}

import {
  to = azurerm_role_assignment.operator_vault_access
  id = "${local.key_vault_id}/providers/Microsoft.Authorization/roleAssignments/${local.operator_role_name}"
}

import {
  to = kubernetes_namespace_v1.pigeon
  id = local.namespace
}

import {
  to = kubernetes_role_v1.deployer
  id = "${local.namespace}/${local.deployer_identity_name}"
}

import {
  to = kubernetes_role_binding_v1.deployer
  id = "${local.namespace}/${local.deployer_identity_name}"
}

import {
  to = github_repository_environment.production
  id = "${local.github_repository}:${local.github_environment}"
}

import {
  to = github_repository_environment_deployment_policy.main
  id = "${local.github_repository}:${local.github_environment}:56330475"
}

import {
  to = github_repository_environment_deployment_policy.rollback
  id = "${local.github_repository}:${local.github_environment}:56330476"
}

import {
  for_each = local.github_environment_variables

  to = github_actions_environment_variable.production[each.key]
  id = "${local.github_repository}:${local.github_environment}:${each.key}"
}
