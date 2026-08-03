resource "kubernetes_namespace_v1" "pigeon" {
  metadata {
    name = local.namespace
    labels = {
      "kubernetes.io/metadata.name"                = local.namespace
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "v1.34"
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "v1.34"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "v1.34"
    }
  }

  lifecycle {
    ignore_changes  = [metadata[0].annotations]
    prevent_destroy = true
  }
}

resource "kubernetes_role_v1" "deployer" {
  metadata {
    name      = local.deployer_identity_name
    namespace = kubernetes_namespace_v1.pigeon.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims", "serviceaccounts", "services"]
    verbs      = ["create", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events", "pods", "pods/log"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["create", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["create", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["secrets-store.csi.x-k8s.io"]
    resources  = ["secretproviderclasses"]
    verbs      = ["create", "get", "list", "patch", "update", "watch"]
  }

  lifecycle {
    ignore_changes  = [metadata[0].annotations]
    prevent_destroy = true
  }
}

resource "kubernetes_role_binding_v1" "deployer" {
  metadata {
    name      = local.deployer_identity_name
    namespace = kubernetes_namespace_v1.pigeon.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployer.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = azurerm_user_assigned_identity.deployer.principal_id
  }

  lifecycle {
    ignore_changes  = [metadata[0].annotations]
    prevent_destroy = true
  }
}
