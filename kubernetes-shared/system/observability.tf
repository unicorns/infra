resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
  }
}

resource "kubernetes_persistent_volume_claim" "data" {
  for_each = toset(["metrics", "logs"])

  metadata {
    name      = "${each.key}-data"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "managed-csi"
    resources {
      requests = { storage = "4Gi" }
    }
  }

  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_cluster_role" "metrics" {
  metadata {
    name = "observability-metrics"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes/proxy"]
    verbs      = ["get"]
  }
}

resource "kubernetes_cluster_role_binding" "metrics" {
  metadata {
    name = "observability-metrics"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.metrics.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "metrics"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }
}

resource "helm_release" "metrics" {
  name       = "metrics"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-metrics-single"
  version    = "0.48.0"
  atomic     = true
  values     = [file("${path.module}/metrics.yaml")]

  depends_on = [kubernetes_persistent_volume_claim.data, kubernetes_cluster_role_binding.metrics]
}

resource "helm_release" "logs" {
  name       = "logs"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-logs-single"
  version    = "0.13.10"
  atomic     = true
  values     = [file("${path.module}/logs.yaml")]

  depends_on = [kubernetes_persistent_volume_claim.data]
}

resource "helm_release" "log_collector" {
  name       = "log-collector"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-logs-collector"
  version    = "0.3.8"
  atomic     = true
  values     = [file("${path.module}/log-collector.yaml")]

  depends_on = [helm_release.logs]
}
