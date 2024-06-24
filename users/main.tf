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


resource "vault_generic_endpoint" "users" {
  for_each = { for user in nonsensitive(var.users) : user.username => user }

  path = "auth/userpass/users/${each.value.username}"
  ignore_absent_fields = true

  data_json = jsonencode({
    policies = each.value.policy_names
    password = each.value.initial_password
  })

  lifecycle {
    # Ignore changes in data_json because any changes will revert the password to the
    # one set here (user password changes will be overwritten).
    ignore_changes = [ data_json ]
  }
}
