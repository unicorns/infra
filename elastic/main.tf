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
}

data "elasticstack_elasticsearch_info" "cluster_info" {
}

resource "elasticstack_elasticsearch_index_lifecycle" "logs" {
  name = "logs"

  metadata = jsonencode({
    description = "default policy for the logs index template installed by x-pack"
    managed = true
  })

  hot {
    min_age = "0ms"

    rollover {
      max_age = "30d"
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
