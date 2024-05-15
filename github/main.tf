terraform {
  cloud {
    organization = "unicornsftw"

    workspaces {
      name = "unicorns-github"
    }
  }

  required_providers {
    github = {
      source = "integrations/github"
      version = ">=6.2.1"
    }
  }
}

variable app_id {
  type = string
  sensitive = true
}

variable installation_id {
  type = string
  sensitive = true
}

variable pem_file {
  type = string
  sensitive = true
}

provider "github" {
  owner = "unicorns"
  app_auth {
    id = var.app_id
    installation_id = var.installation_id
    pem_file = var.pem_file
  }
}

resource github_repository infra {
  name = "infra"
  description = "Infrastructure configuration for the 🦄"
  has_issues = true
  has_projects = true
  vulnerability_alerts = true

  allow_merge_commit = false
  allow_squash_merge = true
  squash_merge_commit_title = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"
  allow_auto_merge = true
  delete_branch_on_merge = true

  # Safety feature to prevent accidental deletion
  archive_on_destroy = true
}
import {
  id = "infra"
  to = github_repository.infra
}

resource tls_private_key infra-deploy-key {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource github_repository_deploy_key "infra" {
  repository = github_repository.infra.name
  title = "Terraform-managed deploy key"
  key = tls_private_key.infra-deploy-key.public_key_openssh
  read_only = false
}

resource github_actions_secret "infra-deploy-key" {
  repository = github_repository.infra.name
  secret_name = "DEPLOY_KEY"
  plaintext_value = tls_private_key.infra-deploy-key.private_key_openssh
}