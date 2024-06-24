variable "kibana_host" {
  type = string
}

resource "kubernetes_namespace" "elastic-stack" {
  metadata {
    name = "elastic-stack"
  }
}


# Enable the use of mmap for efficient index access
# https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-virtual-memory.html#k8s_using_a_daemonset_to_set_virtual_memory
resource "kubernetes_daemonset" "max-map-count-setter" {
  metadata {
    name      = "max-map-count-setter"
    namespace = kubernetes_namespace.elastic-stack.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        name = "max-map-count-setter"
      }
    }

    template {
      metadata {
        labels = {
          name = "max-map-count-setter"
        }
      }

      spec {
        init_container {
          name = "max-map-count-setter"
          image = "docker.io/bash:5.2.21"
          resources {
            limits = {
              cpu    = "100m"
              memory = "32Mi"
            }
          }
          security_context {
            privileged = true
            run_as_user = 0
          }
          command = ["/usr/local/bin/bash", "-e", "-c", "echo 262144 > /proc/sys/vm/max_map_count"]
        }

        container {
          name = "sleep"
          image = "docker.io/bash:5.2.21"
          command = ["sleep", "infinity"]
        }

        dynamic "toleration" {
          for_each = local.azure_spot_node_tolerations

          content {
            key           = toleration.value.key
            operator      = toleration.value.operator
            value         = toleration.value.value
            effect        = toleration.value.effect
          }
        }
      }
    }
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
      "http" = {
        "tls" = {
          "selfSignedCertificate" = {
            # Disable https so that we don't have to deal with X509 certificate errors
            "disabled" = true
          }
        }
      }
      # Don't delete the volume when the cluster is deleted. This is useful for retaining data when we do a reprovision.
      # https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-volume-claim-templates.html#k8s_controlling_volume_claim_deletion
      "volumeClaimDeletePolicy" = "DeleteOnScaledownOnly"
      "nodeSets" = [
        {
          "count" = 1
          "name"  = "default"
          "podTemplate" = {
            "spec" = {
              "initContainers" = [
                {
                  "command" = ["sh", "-c", "while true; do mmc=$(cat /proc/sys/vm/max_map_count); if [ $mmc -eq 262144 ]; then exit 0; fi; sleep 1; done"]
                  "name" = "max-map-count-check"
                },
              ]
              "tolerations" = local.azure_spot_node_tolerations,
              "containers" = [
                {
                  "name" = "elasticsearch"
                  # Reference:
                  # https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-managing-compute-resources.html#k8s-compute-resources
                  "resources" = {
                    "limits" = {
                      "memory" = "4Gi"
                    }
                    "requests" = {
                      "memory" = "2Gi"
                    }
                  }
                }
              ]
            }
          }
          # Reference:
          # https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-volume-claim-templates.html#k8s-volume-claim-templates
          "volumeClaimTemplates" = [
            {
              "metadata" = {
                "name" = "elasticsearch-data"
              }
              "spec" = {
                "accessModes" = ["ReadWriteOnce"]
                "resources" = {
                  "requests" = {
                    "storage" = "64Gi"
                  }
                }
              }
            }
          ]
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

variable "elasticsearch_host" {
  type = string
}

resource "kubectl_manifest" "elasticsearch-es1-ingress" {
  yaml_body = yamlencode({
    "apiVersion" = "networking.k8s.io/v1"
    "kind"       = "Ingress"
    "metadata" = {
      "name"      = "es1-ingress"
      "namespace" = kubernetes_namespace.elastic-stack.metadata[0].name
      "annotations" = {}
    }
    "spec" = {
      "ingressClassName" = "nginx"
      "rules" = [
        {
          "host" = var.elasticsearch_host
          "http" = {
            "paths" = [
              {
                "path" = "/"
                "pathType" = "Prefix"
                "backend" = {
                  "service" = {
                    "name" = "${yamldecode(kubectl_manifest.elasticsearch-es1.yaml_body).metadata.name}-es-http"
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

locals {
  # Derived from https://github.com/elastic/cloud-on-k8s/blob/9dd6dfce933f811cfc307b14c0d2c60cb45c5fe0/config/recipes/elastic-agent/fleet-kubernetes-integration.yaml#L23-L34
  eck_fleet_server_policy = yamldecode(
    <<-EOF
      name: Fleet Server on ECK policy
      id: eck-fleet-server
      namespace: default
      monitoring_enabled:
      - logs
      - metrics
      unenroll_timeout: 900
      package_policies:
      - name: fleet_server-1
        id: fleet_server-1
        package:
          name: fleet_server
    EOF
  )

  # Derived from https://github.com/elastic/cloud-on-k8s/blob/9dd6dfce933f811cfc307b14c0d2c60cb45c5fe0/config/recipes/elastic-agent/fleet-kubernetes-integration.yaml#L35-L48
  eck_agent_policy = yamldecode(
      <<-EOF
        name: Elastic Agent on ECK policy
        id: eck-agent
        namespace: default
        monitoring_enabled:
        - logs
        - metrics
        unenroll_timeout: 900
        package_policies:
        - package:
            name: system
          name: system-1
        - package:
            name: kubernetes
          name: kubernetes-1
      EOF
  )
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
        # Cluster self-monitoring. Accessible via the "Stack Monitoring" tab in Kibana. This is deprecated, but it's much easier to set up than metricbeat.
        "xpack.monitoring.collection.enabled" = "true"
        # Monitoring configuration: https://github.com/elastic/cloud-on-k8s/blob/9dd6dfce933f811cfc307b14c0d2c60cb45c5fe0/config/recipes/elastic-agent/fleet-kubernetes-integration.yaml#L11-L21
        "xpack.fleet.agents.elasticsearch.hosts": ["http://${yamldecode(kubectl_manifest.elasticsearch-es1.yaml_body).metadata.name}-es-http.${kubernetes_namespace.elastic-stack.metadata[0].name}.svc.cluster.local:9200"]
        "xpack.fleet.agents.fleet_server.hosts": ["http://${local.es1_fleet_server_name}-agent-http.${kubernetes_namespace.elastic-stack.metadata[0].name}.svc.cluster.local:8220"]
        "xpack.fleet.packages": [
          {
            "name": "system",
            "version": "latest"
          },
          {
            "name": "elastic_agent",
            "version": "latest"
          },
          {
            "name": "fleet_server",
            "version": "latest"
          },
          {
            "name": "kubernetes",
            "version": "latest"
          }
        ],
        "xpack.fleet.agentPolicies": [
          local.eck_fleet_server_policy,
          local.eck_agent_policy,
        ]
      }
      "http" = {
        "tls" = {
          "selfSignedCertificate" = {
            # We terminate HTTPS at the Ingress, so we don't need HTTPS here.
            "disabled" = true
          }
        }
      }
      "podTemplate" = {
        "spec" = {
          "tolerations" = local.azure_spot_node_tolerations
        }
      }
      "version" = "8.13.4"
    }
  })
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
                    "name" = "${yamldecode(kubectl_manifest.kibana-kb1.yaml_body).metadata.name}-kb-http"
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

################################################################################
# Fleet Server
# Derived from https://github.com/elastic/cloud-on-k8s/blob/9dd6dfce933f811cfc307b14c0d2c60cb45c5fe0/config/recipes/elastic-agent/fleet-kubernetes-integration.yaml
################################################################################

resource "kubernetes_cluster_role" "elastic-fleet-server" {
  metadata {
    name      = "elastic-fleet-server"
  }

  rule {
    api_groups = [""]
    resources = ["pods", "namespaces", "nodes"]
    verbs     = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["get", "create", "update"]
  }
}

resource "kubernetes_service_account" "es1-fleet-server" {
  metadata {
    name      = "es1-fleet-server"
    namespace = kubernetes_namespace.elastic-stack.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "es1-fleet-server" {
  metadata {
    name      = "es1-fleet-server"
  }

  role_ref {
    kind     = "ClusterRole"
    name     = kubernetes_cluster_role.elastic-fleet-server.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.es1-fleet-server.metadata[0].name
    namespace = kubernetes_namespace.elastic-stack.metadata[0].name
  }
}

locals {
  es1_fleet_server_name = "es1-fleet-server"
}

resource "kubectl_manifest" "es1-fleet-server" {
  yaml_body = <<-EOF
    apiVersion: agent.k8s.elastic.co/v1alpha1
    kind: Agent
    metadata:
      name: ${local.es1_fleet_server_name}
      namespace: ${kubernetes_namespace.elastic-stack.metadata[0].name}
    spec:
      version: 8.13.4
      kibanaRef:
        name: ${yamldecode(kubectl_manifest.kibana-kb1.yaml_body).metadata.name}
      elasticsearchRefs:
      - name: ${yamldecode(kubectl_manifest.elasticsearch-es1.yaml_body).metadata.name}
      mode: fleet
      fleetServerEnabled: true
      policyID: ${local.eck_fleet_server_policy.id}
      http:
        tls:
          selfSignedCertificate:
            disabled: true
      deployment:
        replicas: 1
        podTemplate:
          spec:
            serviceAccountName: ${kubernetes_service_account.es1-fleet-server.metadata[0].name}
            automountServiceAccountToken: true
            securityContext:
              runAsUser: 0
            tolerations: ${jsonencode(local.azure_spot_node_tolerations)}
    EOF
}

################################################################################
# Agent
# Derived from https://github.com/elastic/cloud-on-k8s/blob/9dd6dfce933f811cfc307b14c0d2c60cb45c5fe0/config/recipes/elastic-agent/fleet-kubernetes-integration.yaml
################################################################################

resource "kubernetes_cluster_role" "elastic-agent" {
  metadata {
    name      = "elastic-agent"
  }

  rule {
    api_groups = [""]
    resources = ["pods", "nodes", "namespaces", "events", "services", "configmaps"]
    verbs     = ["get", "watch", "list"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["get", "create", "update"]
  }

  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets", "deployments", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes/stats"]
    verbs      = ["get"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_service_account" "es1-elastic-agent" {
  metadata {
    name      = "es1-elastic-agent"
    namespace = kubernetes_namespace.elastic-stack.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "es1-elastic-agent" {
  metadata {
    name      = "es1-elastic-agent"
  }

  role_ref {
    kind     = "ClusterRole"
    name     = kubernetes_cluster_role.elastic-agent.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.es1-elastic-agent.metadata[0].name
    namespace = kubernetes_namespace.elastic-stack.metadata[0].name
  }
}

resource "kubectl_manifest" "es1-elastic-agent" {
  yaml_body = <<-EOF
    apiVersion: agent.k8s.elastic.co/v1alpha1
    kind: Agent
    metadata: 
      name: es1-elastic-agent
      namespace: ${kubernetes_namespace.elastic-stack.metadata[0].name}
    spec:
      version: 8.13.4
      kibanaRef:
        name: ${yamldecode(kubectl_manifest.kibana-kb1.yaml_body).metadata.name}
      fleetServerRef: 
        name: ${yamldecode(kubectl_manifest.es1-fleet-server.yaml_body).metadata.name}
      mode: fleet
      policyID: ${local.eck_agent_policy.id}
      daemonSet:
        podTemplate:
          spec:
            serviceAccountName: ${kubernetes_service_account.es1-elastic-agent.metadata[0].name}
            hostNetwork: true
            dnsPolicy: ClusterFirstWithHostNet
            automountServiceAccountToken: true
            securityContext:
              runAsUser: 0
            tolerations: ${jsonencode(local.azure_spot_node_tolerations)}

            # Mount the necessary directories for the agent to read logs.
            # References:
            # - https://github.com/elastic/cloud-on-k8s/issues/3201#issuecomment-695993095
            # - https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-elastic-agent-fleet-configuration-examples.html#k8s_custom_logs_integration_with_autodiscover
            #   - https://raw.githubusercontent.com/elastic/cloud-on-k8s/2.13/config/recipes/elastic-agent/fleet-custom-logs-integration.yaml
            # - https://raw.githubusercontent.com/elastic/elastic-agent/8.13/deploy/kubernetes/elastic-agent-managed-kubernetes.yaml
            # Mounting /var/log directly mixes logs from the agent and the host, but the agent doesn't appear to have conflicting log files,
            # so it should be fine. This is similar to running the agent on the host directly.
            # The kubernetes and system integrations default to reading directly from /var/log anyway.
            containers:
            - name: agent
              volumeMounts:
              - mountPath: /var/log
                name: varlog
            volumes:
            - name: varlog
              hostPath:
                path: /var/log
    EOF
}
