resource "tfe_workspace" "pigeon_registration" {
  name         = "unicorns-application-pigeon-registration"
  organization = "unicornsftw"
  description  = "State for Pigeon shared-cluster registration"

  lifecycle {
    prevent_destroy = true
  }
}

resource "tfe_workspace_settings" "pigeon_registration" {
  workspace_id   = tfe_workspace.pigeon_registration.id
  execution_mode = "local"

  lifecycle {
    prevent_destroy = true
  }
}
