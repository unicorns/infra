variable "vault_host" {
  type = string
}

resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
  }
}

resource "helm_release" "vault" {
  name       = "hashicorp-vault"
  namespace  = kubernetes_namespace.vault.metadata[0].name
  chart      = "vault"
  repository = "https://helm.releases.hashicorp.com"
  version    = "0.28.0"
  values = [
    yamlencode({
      "server" : {
        "dataStorage" : {
          # Can't use azurefile-csi here because of permission issues during initialization.
          "size" : "1Gi"
        },
        "standalone" : {
          "enabled" : true,
          "config" : <<-EOF
            ui = true

            listener "tcp" {
              tls_disable = 1
              address = "[::]:8200"
              cluster_address = "[::]:8201"
              # Enable unauthenticated metrics access (necessary for Prometheus Operator)
              telemetry {
                unauthenticated_metrics_access = "true"
              }
            }
            storage "raft" {
              path = "/vault/data"
              node_id = "standalone-node"
            }

            # Example configuration for enabling Prometheus metrics in your config.
            telemetry {
              prometheus_retention_time = "30s"
              disable_hostname = true
            }
            EOF
        }
        "auditStorage" : {
          # Note: auditing needs to be enabled separately.
          # https://github.com/hashicorp/vault-helm/blob/72fd0bde9592b23dfb26686070806b22ce6567d8/values.yaml#L790-L794
          "enabled" : "true"
          "size" : "2Gi"
        },
        "ingress" : {
          "enabled" : true,
          "ingressClassName" : "nginx",
          "hosts" : [
            {
              "host" : var.vault_host,
            }
          ]
        },
        "resources" : {
          "requests" : {
            "cpu" : "100m",
            "memory" : "128Mi"
          },
          "limits" : {
            "cpu" : "1",
            "memory" : "256Mi"
          }
        }
      },
      "injector" : {
        "resources" : {
          "requests" : {
            "cpu" : "10m",
            "memory" : "32Mi"
          },
          "limits" : {
            "cpu" : "250m",
            "memory" : "256Mi"
          }
        }
      },
    })
  ]
}