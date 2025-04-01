resource "kubernetes_namespace" "elastic-system" {
  metadata {
    name = "elastic-system"
  }
}

# Docs: https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-install-helm.html
resource "helm_release" "elastic-operator" {
  name       = "elastic-operator"
  namespace  = kubernetes_namespace.elastic-system.metadata[0].name
  chart      = "eck-operator"
  repository = "https://helm.elastic.co"
}
