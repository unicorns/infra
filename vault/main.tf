terraform {
  cloud {
    organization = "unicornsftw"

    workspaces {
      name = "unicorns-vault"
    }
  }

  required_providers {
    vault = {
      source = "hashicorp/vault"
      version = "4.2.0"
    }
  }
}

variable "vault_address" {
  type = string
}

provider "vault" {
  address = var.vault_address
}

# write audit logs to stdout: https://developer.hashicorp.com/vault/docs/audit/file#stdout
resource "vault_audit" "stdout" {
  type = "file"

  options = {
    file_path = "stdout"
  }
}

resource "vault_auth_backend" "userpass" {
  type = "userpass"

  tune {
    default_lease_ttl = "1h"
    max_lease_ttl = "1h"
  }
}

# The provisioner-ro policy allows read access to all secrets.
resource "vault_policy" "provisioner-ro" {
  name   = "provisioner-ro"

  policy = <<-EOF
    path "secret/data/*" {
      capabilities = ["read"]
    }
    EOF
}

# The provisioner-rw policy allows read access to all secrets
# and write access to the outputs.
resource "vault_policy" "provisioner-rw" {
  name   = "provisioner-rw"

  policy = <<-EOF
    path "secret/data/*" {
      capabilities = ["read"]
    }

    path "secret/data/outputs/*" {
      capabilities = ["create", "read", "update"]
    }
    EOF
}

resource "vault_policy" "base-user" {
  name   = "base-user"


  policy = <<-EOF
    path "secret/data/*" {
      capabilities = ["read"]
    }

    # Give users access to sandboxes where they have full control
    path "secret/data/sandbox/{{identity.entity.aliases.${vault_auth_backend.userpass.accessor}.name}}/*" {
      capabilities = ["create", "read", "update", "patch", "delete"]
    }
    path "secret/metadata/sandbox/{{identity.entity.aliases.${vault_auth_backend.userpass.accessor}.name}}/*" {
      capabilities = ["list", "delete"]
    }

    # Allow updating the user's own password using the users/<username> endpoint
    # https://discuss.hashicorp.com/t/a-way-to-allow-a-user-to-change-its-own-password/36555/2
    # https://stackoverflow.com/a/60766959
    # https://stackoverflow.com/a/78475643
    path "auth/${vault_auth_backend.userpass.path}/users/{{identity.entity.aliases.${vault_auth_backend.userpass.accessor}.name}}" {
      capabilities = [ "update" ]
      allowed_parameters = {
        "password" = []
      }
    }

    # Allow updating the user's own password using the users/<username>/password endpoint (used by the web UI)
    # https://github.com/hashicorp/vault/issues/6590#issuecomment-531974848
    path "auth/${vault_auth_backend.userpass.path}/users/{{identity.entity.aliases.${vault_auth_backend.userpass.accessor}.name}}/password" {
      capabilities = [ "update" ]
      allowed_parameters = {
        "password" = []
      }
    }
    EOF
}

resource "random_password" "test-user-password" {
  length = 16
}


resource "vault_generic_endpoint" "test-user" {
  path = "auth/${vault_auth_backend.userpass.path}/users/test-user"
  ignore_absent_fields = true

  data_json = jsonencode({
    policies = [vault_policy.base-user.name]
    password = random_password.test-user-password.result
  })

  lifecycle {
    # Ignore changes in data_json because any changes will revert the password to the
    # one set here (user password changes will be overwritten).
    ignore_changes = [ data_json ]
  }
}

output "test-user-password" {
  value = random_password.test-user-password.result
  sensitive = true
}

resource "vault_jwt_auth_backend" "github-actions" {
  description = "GitHub Actions JWT Auth"
  path = "jwt"
  oidc_discovery_url = "https://token.actions.githubusercontent.com"
  bound_issuer = "https://token.actions.githubusercontent.com"
}

variable "github_actions_unicorns_infra_jwt_role_name_ro" {
  type = string
}

resource "vault_jwt_auth_backend_role" "github-actions-unicorns-infra-ro" {
  backend = vault_jwt_auth_backend.github-actions.path
  role_name = var.github_actions_unicorns_infra_jwt_role_name_ro
  user_claim = "actor"
  bound_claims = {
    "repository" = "unicorns/infra"
    # TODO: branch?
  }
  token_policies = [vault_policy.provisioner-ro.name]
  role_type = "jwt"
  token_ttl = 1 * pow(60, 2) # pow(60, 2) = 1 hour (in seconds)
  token_max_ttl = 1 * pow(60, 2) # pow(60, 2) = 1 hour (in seconds)
}

variable "github_actions_unicorns_infra_jwt_role_name_rw" {
  type = string
}

resource "vault_jwt_auth_backend_role" "github-actions-unicorns-infra-rw" {
  backend = vault_jwt_auth_backend.github-actions.path
  role_name = var.github_actions_unicorns_infra_jwt_role_name_rw
  user_claim = "actor"
  bound_claims = {
    # A list of available options: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token
    "repository" = "unicorns/infra"
    # TODO: branch?
  }
  token_policies = [vault_policy.provisioner-rw.name]
  role_type = "jwt"
  token_ttl = 1 * pow(60, 2) # pow(60, 2) = 1 hour (in seconds)
  token_max_ttl = 1 * pow(60, 2) # pow(60, 2) = 1 hour (in seconds)
}