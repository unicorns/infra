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

data github_repository "infra" {
  name = "infra"
}

resource tls_private_key infra-deploy-key {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource github_repository_deploy_key "infra" {
  repository = data.github_repository.infra.name
  title = "Terraform-managed deploy key"
  key = tls_private_key.infra-deploy-key.public_key_openssh
  read_only = false
}

resource github_actions_secret "infra-deploy-key" {
  repository = data.github_repository.infra.name
  secret_name = "DEPLOY_KEY"
  plaintext_value = tls_private_key.infra-deploy-key.private_key_openssh
}