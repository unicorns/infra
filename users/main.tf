terraform {
  cloud {
    organization = "unicornsftw"

    workspaces {
      name = "unicorns-users"
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

variable "users" {
  type = list(object({
    username = string
    policy_names = list(string)
    initial_password = string
  }))
  sensitive = true
}

locals {
  usernames = nonsensitive(toset([ for user in var.users : user.username ]))
  users = { for user in var.users : user.username => user }
}

resource "vault_generic_endpoint" "user_passwords" {
  for_each = local.usernames

  path = "auth/userpass/users/${each.key}"
  ignore_absent_fields = true
  disable_read = true # disable drift detection. We don't update this anyway.

  data_json = jsonencode({
    password = local.users[each.key].initial_password
  })

  lifecycle {
    # Ignore changes in data_json because any changes will revert the password to the
    # one set here (user password changes will be overwritten).
    ignore_changes = [ data_json ]
  }
}

resource "vault_generic_endpoint" "user_policies" {
  depends_on = [ vault_generic_endpoint.user_passwords ]

  for_each = local.usernames

  path = "auth/userpass/users/${each.key}"
  ignore_absent_fields = true
  disable_delete = true # the lifecycle of this auth method is managed by the user_passwords resource

  data_json = jsonencode({
    policies = local.users[each.key].policy_names
  })
}
