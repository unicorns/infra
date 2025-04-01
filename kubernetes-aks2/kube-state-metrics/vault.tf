resource "kubernetes_namespace" "kube-state-metrics" {
  metadata {
    name = "kube-state-metrics"
  }
}

resource "helm_release" "kube-state-metrics" {
  name       = "kube-state-metrics"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  namespace  = kubernetes_namespace.kube-state-metrics.metadata.0.name

  set {
    name = "resources.requests.cpu"
    value = "10m"
  }
  set {
    name = "resources.requests.memory"
    value = "32Mi"
  }

  set {
    name = "resources.limits.cpu"
    value = "100m"
  }
  set {
    name = "resources.limits.memory"
    value = "250Mi"
  }
}