# Reloader restarts annotated pods when their ConfigMaps or Secrets change.
# https://github.com/stakater/Reloader

resource "kubernetes_namespace" "reloader" {
  metadata {
    name = "reloader"
  }
}

resource "helm_release" "reloader" {
  name       = "stakater"
  namespace  = kubernetes_namespace.reloader.metadata[0].name
  chart      = "reloader"
  repository = "https://stakater.github.io/stakater-charts"
  version    = "v1.0.51"

  values = [<<EOF
    reloader:
      reloadStrategy: annotations
      deployment:
        replicas: 1
      resources:
        requests:
          cpu: 10m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi
  EOF
  ]
}
