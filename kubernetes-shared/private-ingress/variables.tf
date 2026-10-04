variable "acme_email" {
  type        = string
  description = "Contact email for the private ingress ACME account"

  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.acme_email))
    error_message = "The ACME contact must be an email address."
  }
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID for benzhang.dev"

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.cloudflare_zone_id))
    error_message = "The Cloudflare zone ID must contain 32 lowercase hexadecimal characters."
  }
}

variable "tailscale_client_id" {
  type        = string
  description = "Tailscale trust credential bound to the operator's Kubernetes ServiceAccount"

  validation {
    condition     = length(trimspace(var.tailscale_client_id)) > 0
    error_message = "A Tailscale workload identity client ID is required."
  }
}

variable "tailscale_audience" {
  type        = string
  description = "Audience expected by the Tailscale workload identity trust credential"

  validation {
    condition     = length(trimspace(var.tailscale_audience)) > 0
    error_message = "A Tailscale workload identity audience is required."
  }
}

locals {
  namespace         = "private-ingress"
  domain            = "benzhang.dev"
  gateway           = "private-traefik"
  ingress_class     = "tailnet"
  proxy_group       = "unicorns-private"
  operator_tag      = "tag:unicorns-k8s-operator"
  proxy_tag         = "tag:unicorns-private-ingress"
  cloudflare_secret = "cloudflare-api-token"
  acme_claim        = "private-traefik-acme"
}
