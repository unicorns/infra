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

resource "vault_auth_backend" "userpass" {
  type = "userpass"

  tune {
    default_lease_ttl = "1h"
    max_lease_ttl = "1h"
  }
}

# The base-provisioner policy allows read access to all secrets
# and write access to the outputs.
resource "vault_policy" "base-provisioner" {
  name   = "base-provisioner"

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

    # Allow the user to read and write to their own secrets
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