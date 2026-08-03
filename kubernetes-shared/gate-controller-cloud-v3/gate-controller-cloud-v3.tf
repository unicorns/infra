variable "host" {
  type = string
}

variable "image" {
  type = string
}

variable "storage_size" {
  type    = string
  default = "1Gi"
}

variable "initial_admin_credentials_secret_name" {
  type    = string
  default = "gate-controller-cloud-v3-initial-admin-credentials"
}

variable "agent_token_secret_name" {
  type    = string
  default = "gate-controller-cloud-v3-agent-token"
}

variable "openai_api_key_secret_name" {
  type    = string
  default = "gate-controller-cloud-v3-openai-api-key"
}

locals {
  app_name  = "gate-controller-cloud-v3"
  namespace = "gate-controller-cloud-v3"

  secret_provider_objects = <<-EOF
array:
  - |
    objectName: ${var.initial_admin_credentials_secret_name}
    objectType: secret
    objectAlias: initial-admin-credentials
  - |
    objectName: ${var.agent_token_secret_name}
    objectType: secret
    objectAlias: agent-token
  - |
    objectName: ${var.openai_api_key_secret_name}
    objectType: secret
    objectAlias: openai-api-key
  EOF
}

resource "kubernetes_namespace" "gate_controller" {
  metadata {
    name = local.namespace
  }
}

resource "kubectl_manifest" "gate_controller_secrets" {
  yaml_body = yamlencode({
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = local.app_name
      namespace = kubernetes_namespace.gate_controller.metadata[0].name
    }
    spec = {
      provider = "azure"
      parameters = {
        usePodIdentity         = "false"
        useVMManagedIdentity   = "true"
        userAssignedIdentityID = var.key_vault_secret_provider_client_id
        keyvaultName           = var.key_vault_name
        tenantId               = var.key_vault_tenant_id
        objects                = local.secret_provider_objects
      }
    }
  })
}

resource "kubernetes_persistent_volume_claim_v1" "gate_controller_data" {
  metadata {
    name      = "${local.app_name}-data"
    namespace = kubernetes_namespace.gate_controller.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "managed-csi"

    resources {
      requests = {
        storage = var.storage_size
      }
    }
  }

  wait_until_bound = false
}

resource "kubernetes_deployment_v1" "gate_controller" {
  metadata {
    name      = local.app_name
    namespace = kubernetes_namespace.gate_controller.metadata[0].name
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = local.app_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.app_name
        }
      }

      spec {
        toleration {
          key      = "kubernetes.azure.com/scalesetpriority"
          operator = "Equal"
          value    = "spot"
          effect   = "NoSchedule"
        }

        container {
          name              = local.app_name
          image             = var.image
          image_pull_policy = "Always"

          command = ["/bin/sh", "-c"]
          args = [<<-EOF
            set -eu
            export INITIAL_ADMIN_CREDENTIALS="$(cat /mnt/secrets-store/initial-admin-credentials)"
            if [ -f /mnt/secrets-store/agent-token ]; then
              export AGENT_TOKEN="$(cat /mnt/secrets-store/agent-token)"
            fi
            if [ -f /mnt/secrets-store/openai-api-key ]; then
              export OPENAI_API_KEY="$(cat /mnt/secrets-store/openai-api-key)"
            fi
            exec npm run prod:all
          EOF
          ]

          port {
            name           = "http"
            container_port = 3000
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "768Mi"
            }
          }

          readiness_probe {
            tcp_socket {
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            tcp_socket {
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          volume_mount {
            name       = "secrets"
            mount_path = "/mnt/secrets-store"
            read_only  = true
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.gate_controller_data.metadata[0].name
          }
        }

        volume {
          name = "secrets"

          csi {
            driver    = "secrets-store.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = local.app_name
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubectl_manifest.gate_controller_secrets,
  ]
}

resource "kubernetes_service_v1" "gate_controller" {
  metadata {
    name      = local.app_name
    namespace = kubernetes_namespace.gate_controller.metadata[0].name
  }

  spec {
    selector = {
      app = local.app_name
    }

    port {
      name        = "http"
      port        = 80
      target_port = 3000
    }
  }
}

resource "kubernetes_ingress_v1" "gate_controller" {
  metadata {
    name      = local.app_name
    namespace = kubernetes_namespace.gate_controller.metadata[0].name
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.gate_controller.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

output "gate_controller_host" {
  value = var.host
}

output "gate_controller_image" {
  value = var.image
}
