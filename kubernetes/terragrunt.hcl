# this file does not define any resources 
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

terraform {
  extra_arguments "var-files" {
    commands = get_terraform_commands_that_need_vars()

    optional_var_files = [
      "${get_env("PROV_RUN_DIR")}/terraform.tfvars",
      "${get_env("PROV_RUN_DIR")}/terraform.tfvars.json",
    ]
  }
}

generate backend {
  path = "common_backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<-EOF
    terraform {
      backend "remote" {
        hostname = "app.terraform.io"
        organization = "unicornsftw"

        workspaces {
          name = "unicorns-kubernetes-${path_relative_to_include()}"
        }
      }
    }
  EOF
}

generate provider {
  path = "common_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents = file("./_common/providers.tf")
}

generate variables {
  path = "common_variables.tf"
  if_exists = "overwrite_terragrunt"
  contents = file("./_common/variables.tf")
}

generate locals {
  path = "common_locals.tf"
  if_exists = "overwrite_terragrunt"
  contents = file("./_common/locals.tf")
}