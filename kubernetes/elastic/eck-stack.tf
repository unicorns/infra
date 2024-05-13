variable "kibana_host" {
  type = string
}

resource "kubernetes_namespace" "elastic-stack" {
  metadata {
    name = "elastic-stack"
  }
}

# Docs: https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-elasticsearch.html
resource "kubectl_manifest" "elasticsearch-es1" {
  yaml_body = yamlencode({
    "apiVersion" = "elasticsearch.k8s.elastic.co/v1"
    "kind"       = "Elasticsearch"
    "metadata" = {
      "name"      = "es1"
      "namespace" = kubernetes_namespace.elastic-stack.metadata[0].name
    }
    "spec" = {
      "nodeSets" = [
        {
          "count" = 1
          "name"  = "default"
          "podTemplate" = {
            "spec" = {
              "initContainers" = [
                # Enable the use of mmap for efficient index access
                # https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-virtual-memory.html#k8s_using_an_init_container_to_set_virtual_memory
                {
                  "command" = [
                    "sh",
                    "-c",
                    "sysctl -w vm.max_map_count=262144",
                  ]
                  "name" = "sysctl"
                  "securityContext" = {
                    "privileged" = true
                    "runAsUser"  = 0
                  }
                },
              ]
              "tolerations" = local.azure_spot_node_tolerations
            }
          }
        },
      ]
      "version" = "8.13.4"
    }
  })
}

data "kubernetes_secret" "es1-user" {
  metadata {
    name      = "${yamldecode(kubectl_manifest.elasticsearch-es1.yaml_body).metadata.name}-es-elastic-user"
    namespace = kubernetes_namespace.elastic-stack.metadata[0].name
  }
}

output "es1_elastic_user_password" {
  value = data.kubernetes_secret.es1-user.data["elastic"]
  sensitive = true
}

resource "kubectl_manifest" "kibana-kb1" {
  yaml_body = yamlencode({
    "apiVersion" = "kibana.k8s.elastic.co/v1"
    "kind"       = "Kibana"
    "metadata" = {
      "name"      = "kb1"
      "namespace" = kubernetes_namespace.elastic-stack.metadata[0].name
    }
    "spec" = {
      "count" = 1
      "elasticsearchRef" = {
        "name" = yamldecode(kubectl_manifest.elasticsearch-es1.yaml_body).metadata.name
      }
      "config" = {
        "server.publicBaseUrl" = "https://${var.kibana_host}"
      }
      "http" = {
        "tls" = {
          "selfSignedCertificate" = {
            # We terminate HTTPS at the Ingress, so we don't need HTTPS here.
            "disabled" = true
          }
        }
      }
      "version" = "8.13.4"
    }
  })
}

data "kubernetes_service" "kb1" {
  metadata {
    name      = "${yamldecode(kubectl_manifest.kibana-kb1.yaml_body).metadata.name}-kb-http"
    namespace = kubernetes_namespace.elastic-stack.metadata[0].name
  }
}

resource "kubectl_manifest" "kibana-kb1-ingress" {
  yaml_body = yamlencode({
    "apiVersion" = "networking.k8s.io/v1"
    "kind"       = "Ingress"
    "metadata" = {
      "name"      = "kb1-ingress"
      "namespace" = kubernetes_namespace.elastic-stack.metadata[0].name
      "annotations" = {}
    }
    "spec" = {
      "ingressClassName" = "nginx"
      "rules" = [
        {
          "host" = var.kibana_host
          "http" = {
            "paths" = [
              {
                "path" = "/"
                "pathType" = "Prefix"
                "backend" = {
                  "service" = {
                    "name" = data.kubernetes_service.kb1.metadata[0].name
                    "port" = {
                      "name" = "http"
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  })
}
