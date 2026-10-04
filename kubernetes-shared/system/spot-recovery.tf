resource "kubernetes_config_map" "autoscaler_priorities" {
  metadata {
    name      = "cluster-autoscaler-priority-expander"
    namespace = "kube-system"
  }

  data = {
    priorities = yamlencode({
      "50" = [".*appspot.*"]
      "10" = [".*appbackup.*"]
    })
  }
}

resource "helm_release" "spot_return" {
  name       = "spot-return"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/descheduler/"
  chart      = "descheduler"
  version    = "0.35.1"
  atomic     = true
  values     = [file("${path.module}/spot-return.yaml")]
}
