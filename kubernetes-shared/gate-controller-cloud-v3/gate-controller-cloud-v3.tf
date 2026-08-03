terraform {
  required_version = ">= 1.8.0"
}

# These resources remain live while management moves to ben-z/gate-controller.
removed {
  from = kubernetes_namespace.gate_controller

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.gate_controller_secrets

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_persistent_volume_claim_v1.gate_controller_data

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_deployment_v1.gate_controller

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.gate_controller

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_ingress_v1.gate_controller

  lifecycle {
    destroy = false
  }
}
