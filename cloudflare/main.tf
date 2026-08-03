terraform {
  required_version = ">= 1.8.0"

  cloud {
    organization = "unicornsftw"

    workspaces {
      name = "unicorns-cloudflare"
    }
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.52.0"
    }
  }
}

# The record remains live while ownership moves out of this repository.
removed {
  from = cloudflare_record.gate_controller

  lifecycle {
    destroy = false
  }
}
