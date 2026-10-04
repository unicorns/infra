resource "kubernetes_config_map" "autoscaler_priorities" {
  metadata {
    name      = "cluster-autoscaler-priority-expander"
    namespace = "kube-system"
  }

  data = {
    priorities = yamlencode({
      "50" = [".*-appspot-.*"]
      "10" = [".*-appspotalt-.*"]
    })
  }
}
