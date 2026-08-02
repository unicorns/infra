terraform {
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

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "zone_name" {
  type    = string
  default = "benzhang.dev"
}

variable "gate_controller_hostname" {
  type    = string
  default = "gate-controller-cloud-v3.benzhang.dev"
}

variable "gate_controller_origin_ip" {
  type        = string
  description = "Public ingress IP for the shared AKS ingress controller"
}

variable "gate_controller_proxied" {
  type    = bool
  default = true
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "cloudflare_zone" "primary" {
  name = var.zone_name
}

resource "cloudflare_record" "gate_controller" {
  zone_id = data.cloudflare_zone.primary.id
  name    = var.gate_controller_hostname
  type    = "A"
  content = var.gate_controller_origin_ip
  proxied = var.gate_controller_proxied
  ttl     = 1
  comment = "Managed by Terraform"
}

output "gate_controller_hostname" {
  value = cloudflare_record.gate_controller.hostname
}

output "gate_controller_origin_ip" {
  value = cloudflare_record.gate_controller.content
}

output "gate_controller_proxied" {
  value = cloudflare_record.gate_controller.proxied
}
