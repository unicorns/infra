variable "host" {
  type = string
}

variable "initial_admin_credentials" {
  type = string
  sensitive = true
}

resource "kubernetes_namespace" "gate-controller-cloud-v3" {
  metadata {
    name = "gate-controller-cloud-v3"
  }
}

resource "kubernetes_persistent_volume_claim_v1" "gate-controller-cloud-v3-data" {
  metadata {
    name = "gate-controller-cloud-v3-data"
    namespace = kubernetes_namespace.gate-controller-cloud-v3.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
  wait_until_bound = false
}

resource "kubernetes_secret" "gate-controller-cloud-v3-initial-admin-credentials" {
  metadata {
    name = "gate-controller-cloud-v3-initial-admin-credentials"
    namespace = kubernetes_namespace.gate-controller-cloud-v3.metadata[0].name
  }
  data = {
    "initial_admin_credentials" = var.initial_admin_credentials
  }
}

resource "kubernetes_deployment_v1" "gate-controller-cloud-v3" {
  metadata {
    name = "gate-controller-cloud-v3"
    namespace = kubernetes_namespace.gate-controller-cloud-v3.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "gate-controller-cloud-v3"
      }
    }
    template {
      metadata {
        labels = {
          app = "gate-controller-cloud-v3"
        }
      }
      spec {
        container {
          name = "gate-controller-cloud-v3"
          image = "ghcr.io/ben-z/gate-controller/cloud-v3:sha-4c02a358ad2fcf12d66a8a48c06ca621ea2a6552@sha256:b38d8632f75833504013c5745fea2adca1fdb457b2f49c8ff250bbb42f8731b0"

          env {
            name = "INITIAL_ADMIN_CREDENTIALS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.gate-controller-cloud-v3-initial-admin-credentials.metadata[0].name
                key = "initial_admin_credentials"
              }
            }
          }

          volume_mount {
            name = "gate-controller-cloud-v3-data"
            mount_path = "/data"
          }
        }
        volume {
          name = "gate-controller-cloud-v3-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.gate-controller-cloud-v3-data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "gate-controller-cloud-v3" {
  metadata {
    name = "gate-controller-cloud-v3"
    namespace = kubernetes_namespace.gate-controller-cloud-v3.metadata[0].name
  }
  spec {
    selector = {
      app = "gate-controller-cloud-v3"
    }
    port {
      port = 80
      target_port = 3000
    }
  }
}

resource "kubernetes_ingress_v1" "gate-controller-cloud-v3" {
  metadata {
    name = "gate-controller-cloud-v3"
    namespace = kubernetes_namespace.gate-controller-cloud-v3.metadata[0].name
  }
  spec {
    ingress_class_name = "nginx"
    rule {
      host = var.host
      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service_v1.gate-controller-cloud-v3.metadata[0].name
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