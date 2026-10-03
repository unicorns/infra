include "root" {
  path = find_in_parent_folders()
}

locals {
  subproj_name = path_relative_to_include()
}

terraform {
  source = "."

  extra_arguments "subproj-var-files" {
    commands = get_terraform_commands_that_need_vars()

    optional_var_files = [
      "${get_env("PROV_RUN_DIR")}/${local.subproj_name}/terraform.tfvars",
      "${get_env("PROV_RUN_DIR")}/${local.subproj_name}/terraform.tfvars.json",
    ]
  }
}
