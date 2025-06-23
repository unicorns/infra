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

# MARK: Mounts
resource "vault_mount" "users" {
  type = "kv-v2"
  path = "users"
  description = "A mount for user data"
}

resource "vault_mount" "sandbox" {
  type = "kv-v2"
  path = "sandbox"
  description = "A mount for sandbox (dev) data"
}

# MARK: Auth backends
resource "vault_auth_backend" "userpass" {
  type = "userpass"

  tune {
    default_lease_ttl = "1h"
    max_lease_ttl = "1h"
  }
}

# MARK: Policies
# The provisioner-ro policy allows read access to all secrets.
resource "vault_policy" "provisioner-ro" {
  name   = "provisioner-ro"

  policy = <<-EOF
    # Read access to secrets
    path "secret/data/*" {
      capabilities = ["read"]
    }

    # Read access to user data
    path "${vault_mount.users.path}/data/*" {
      capabilities = ["read"]
    }
    path "${vault_mount.users.path}/metadata/*" {
      capabilities = ["list"]
    }
    EOF
}

# The provisioner-rw policy allows read access to all secrets
# and write access to the outputs and states (for backup) paths.
resource "vault_policy" "provisioner-rw" {
  name   = "provisioner-rw"

  policy = <<-EOF
    # Read access to secrets
    path "secret/data/*" {
      capabilities = ["read"]
    }

    # Read access to user data
    path "${vault_mount.users.path}/data/*" {
      capabilities = ["read"]
    }
    path "${vault_mount.users.path}/metadata/*" {
      capabilities = ["list"]
    }

    # Write access to userpass auth backend
    path "auth/${vault_auth_backend.userpass.path}/users/*" {
      capabilities = ["create", "read", "update", "delete"]
    }

    # Write access to outputs
    path "secret/data/outputs/*" {
      capabilities = ["create", "read", "update"]
    }

    # Write access to state backups
    path "secret/data/states/*" {
      capabilities = ["create", "read", "update"]
    }

    # Allow creating child tokens. Otherwise we'll need to enable skip_child_token when using this policy with
    # vault providers.
    # https://support.hashicorp.com/hc/en-us/articles/360034820694-Parent-Child-Token-Hierarchy
    path "auth/token/create" {
      capabilities = ["create", "update"]
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
    path "${vault_mount.sandbox.path}/data/users/{{identity.entity.aliases.${vault_auth_backend.userpass.accessor}.name}}/*" {
      capabilities = ["create", "read", "update", "patch", "delete"]
    }
    path "${vault_mount.sandbox.path}/metadata/users/{{identity.entity.aliases.${vault_auth_backend.userpass.accessor}.name}}/*" {
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

    # Allow creating child tokens. Otherwise we'll need to enable skip_child_token when using this policy with
    # vault providers.
    # https://support.hashicorp.com/hc/en-us/articles/360034820694-Parent-Child-Token-Hierarchy
    path "auth/token/create" {
      capabilities = ["create", "update"]
    }
    EOF
}

output "vault_policy_names" {
  value = [
    vault_policy.provisioner-ro.name,
    vault_policy.provisioner-rw.name,
    vault_policy.base-user.name,
  ]
}

# MARK: JWT Auth Roles
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
  # Docs: https://github.com/hashicorp/vault-action/blob/0f302fb182aed807f79e2c0558e3250bbc27b043/README.md#jwt-with-github-oidc-tokens
  # A list of available options: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token
  bound_claims = {
    "repository" = "unicorns/infra",
  }
  bound_audiences = ["https://github.com/unicorns"]
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
  # Docs: https://github.com/hashicorp/vault-action/blob/0f302fb182aed807f79e2c0558e3250bbc27b043/README.md#jwt-with-github-oidc-tokens
  # A list of available options: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token
  bound_claims = {
    "ref" = "refs/heads/main",
    "ref_type" = "branch",
    "repository" = "unicorns/infra",
  }
  token_policies = [vault_policy.provisioner-rw.name]
  role_type = "jwt"
  token_ttl = 1 * pow(60, 2) # pow(60, 2) = 1 hour (in seconds)
  token_max_ttl = 1 * pow(60, 2) # pow(60, 2) = 1 hour (in seconds)
}