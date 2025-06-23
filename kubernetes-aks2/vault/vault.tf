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
  version    = "0.30.0"
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
        "ingress" : {
          "enabled" : true,
          "ingressClassName" : "nginx",
          "annotations" : {
            # Allow for larger body sizes. Used for restoring raft snapshots.
            "nginx.ingress.kubernetes.io/proxy-body-size" : "100m",
          },
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