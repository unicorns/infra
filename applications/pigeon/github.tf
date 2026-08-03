resource "github_repository_environment" "production" {
  repository  = local.github_repository
  environment = local.github_environment

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_environment_deployment_policy" "main" {
  repository     = local.github_repository
  environment    = github_repository_environment.production.environment
  branch_pattern = "main"

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_environment_deployment_policy" "rollback" {
  repository     = local.github_repository
  environment    = github_repository_environment.production.environment
  branch_pattern = "rollback/*"

  lifecycle {
    prevent_destroy = true
  }
}

data "github_repository_environment_deployment_policies" "production" {
  repository  = local.github_repository
  environment = github_repository_environment.production.environment

  depends_on = [
    github_repository_environment_deployment_policy.main,
    github_repository_environment_deployment_policy.rollback,
  ]
}

locals {
  expected_github_deployment_policies = toset([
    "branch:main",
    "branch:rollback/*",
  ])
  actual_github_deployment_policies = toset([
    for policy in data.github_repository_environment_deployment_policies.production.policies :
    "${policy.type}:${policy.pattern}"
  ])
}

resource "terraform_data" "github_deployment_policies_are_exclusive" {
  input = local.actual_github_deployment_policies

  lifecycle {
    precondition {
      condition = (
        length(data.github_repository_environment_deployment_policies.production.policies) == 2 &&
        local.actual_github_deployment_policies == local.expected_github_deployment_policies
      )
      error_message = "Pigeon production deployment policies must be exactly branch:main and branch:rollback/*, with no extras."
    }
  }
}

resource "github_actions_environment_variable" "production" {
  for_each = local.github_environment_variables

  repository    = local.github_repository
  environment   = github_repository_environment.production.environment
  variable_name = each.key
  value         = each.value

  lifecycle {
    prevent_destroy = true
  }
}
