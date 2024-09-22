terraform {
  cloud {
    organization = "unicornsftw"

    workspaces {
      name = "unicorns-elastic"
    }
  }

  required_providers {
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "0.11.4"
    }
  }
}

variable "elastic_password" {
  type        = string
  description = "The password for the elastic user"
  sensitive   = true
}

provider "elasticstack" {
  elasticsearch {
    username  = "elastic"
    password  = var.elastic_password
    endpoints = ["https://elasticsearch.benzhang.dev"]
  }
  kibana {
    username  = "elastic"
    password  = var.elastic_password
    endpoints = ["https://kibana.benzhang.dev"]
  }
}

data "elasticstack_elasticsearch_info" "cluster_info" {
}

resource "elasticstack_elasticsearch_index_lifecycle" "logs" {
  name = "logs"

  metadata = jsonencode({
    description = "[Managed by Terraform] (Modified) default policy for the logs index template installed by x-pack"
    managed     = true
  })

  hot {
    min_age = "0ms"

    rollover {
      max_age                = "30d"
      max_primary_shard_size = "10gb"
    }
  }

  delete {
    min_age = "5d"
    delete {}
  }
}
import {
  to = elasticstack_elasticsearch_index_lifecycle.logs
  id = "${data.elasticstack_elasticsearch_info.cluster_info.cluster_uuid}/logs"
}

resource "elasticstack_elasticsearch_index_lifecycle" "metrics" {
    name = "metrics"

    metadata = jsonencode({
      description = "[Managed by Terraform] (Modified) default policy for the metrics index template installed by x-pack"
      managed     = true
    })

    hot {
      min_age = "0ms"

      rollover {
        max_age                = "30d"
        max_primary_shard_size = "50gb"
      }
    }

    delete {
      min_age = "30d"
      delete {}
    }
}
import {
  to = elasticstack_elasticsearch_index_lifecycle.metrics
  id = "${data.elasticstack_elasticsearch_info.cluster_info.cluster_uuid}/metrics"
}

resource "elasticstack_fleet_integration" "kubernetes" {
  name    = "kubernetes"
  version = "1.58.0"
}

resource "elasticstack_fleet_agent_policy" "eck-agent" {
  name      = "Elastic Agent on ECK policy (managed by Terraform)"
  namespace = "default"

  monitor_logs    = true
  monitor_metrics = true
}
import {
  to = elasticstack_fleet_agent_policy.eck-agent
  # This is a preconfigured policy from the ECK stack
  id = "eck-agent"
}

locals {
  # Deployed using the Kubernetes provisioner
  kube_state_metrics_stream_vars = {
    hosts = ["kube-state-metrics.kube-state-metrics.svc.cluster.local:8080"],

    # Default settings to prevent perpetual diffs
    add_metadata                  = true
    bearer_token_file             = "/var/run/secrets/kubernetes.io/serviceaccount/token"
    leaderelection                = true
    period                        = "10s"
    "ssl.certificate_authorities" = []
  }
}

resource "elasticstack_fleet_integration_policy" "eck-agent-kubernetes" {
  name                = "Kubernetes Integration (managed by Terraform)"
  namespace           = "default"
  agent_policy_id     = elasticstack_fleet_agent_policy.eck-agent.id
  integration_name    = elasticstack_fleet_integration.kubernetes.name
  integration_version = elasticstack_fleet_integration.kubernetes.version

  input {
    input_id = "kubelet-kubernetes/metrics"
  }
  input {
    input_id = "kube-state-metrics-kubernetes/metrics"
    streams_json = jsonencode(merge(
      {
        for name in [
          "kubernetes.state_cronjob",
          "kubernetes.state_daemonset",
          "kubernetes.state_deployment",
          "kubernetes.state_job",
          "kubernetes.state_namespace",
          "kubernetes.state_node",
          "kubernetes.state_persistentvolume",
          "kubernetes.state_persistentvolumeclaim",
          "kubernetes.state_replicaset",
          "kubernetes.state_resourcequota",
          "kubernetes.state_service",
          "kubernetes.state_statefulset",
          "kubernetes.state_storageclass",
        ] :
        name => {
          enabled = true
          vars    = local.kube_state_metrics_stream_vars
        }
      },
      {
        # These streams have extra variables
        for name in [
          "kubernetes.state_container",
          "kubernetes.state_pod",
        ] :
        name => {
          enabled = true
          vars = merge(local.kube_state_metrics_stream_vars, {
            add_resource_metadata_config = ""
          })
        }
      }
    ))
  }
  input {
    input_id = "kube-apiserver-kubernetes/metrics"
  }
  input {
    input_id = "kube-proxy-kubernetes/metrics"
  }
  input {
    input_id = "kube-scheduler-kubernetes/metrics"
    enabled  = false
  }
  input {
    input_id = "kube-controller-manager-kubernetes/metrics"
    enabled  = false
  }
  input {
    input_id = "events-kubernetes/metrics"
  }
  input {
    input_id = "container-logs-filestream"
  }
  input {
    input_id = "audit-logs-filestream"
    enabled  = false
  }
}
import {
  to = elasticstack_fleet_integration_policy.eck-agent-kubernetes
  # Manually obtained from https://kibana.benzhang.dev/app/fleet/policies/eck-agent/edit-integration/a3b718bd-efec-54f4-b513-7711c744a8ec
  # In the future, we should configure an empty package policy list in the eck-stack provisioner and
  # define the package policy here instead.
  id = "a3b718bd-efec-54f4-b513-7711c744a8ec"
}
