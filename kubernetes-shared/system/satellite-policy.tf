locals {
  satellite_admission_rules = {
    pod = {
      apiGroups = [""]
      resources = ["pods"]
      validations = [
        {
          expression = "has(object.spec.nodeSelector) && 'kubernetes.azure.com/mode' in object.spec.nodeSelector && object.spec.nodeSelector['kubernetes.azure.com/mode'] == 'user'"
          message    = "Satellite Pods must select AKS user nodes to protect system capacity."
        }
      ]
    }
    ingress = {
      apiGroups = ["networking.k8s.io"]
      resources = ["ingresses"]
      validations = [
        {
          expression = "has(object.spec.ingressClassName) && object.spec.ingressClassName in ['public', 'tailnet']"
          message    = "Satellite Ingresses must use the public or tailnet class."
        },
        {
          expression = "has(object.spec.rules) && size(object.spec.rules) > 0 && object.spec.rules.all(rule, has(rule.host) && rule.host == request.namespace + '.benzhang.dev')"
          message    = "Each satellite Ingress host must be <namespace>.benzhang.dev."
        },
        {
          expression = "has(object.spec.rules) && object.spec.rules.all(rule, has(rule.http) && has(rule.http.paths) && size(rule.http.paths) > 0 && rule.http.paths.all(path, has(path.backend.service) && !has(path.backend.resource)))"
          message    = "Each satellite Ingress rule must have HTTP paths that reference Services in its own namespace."
        },
        {
          expression = "!has(object.spec.defaultBackend) && !has(object.spec.tls)"
          message    = "Satellite Ingresses must use explicit host rules and platform TLS."
        },
        {
          expression = "!has(object.metadata.annotations) || object.metadata.annotations.all(key, key == 'kubectl.kubernetes.io/last-applied-configuration')"
          message    = "Satellite Ingress annotations are limited to kubectl metadata; the platform owns gateway configuration."
        }
      ]
    }
    service = {
      apiGroups = [""]
      resources = ["services"]
      validations = [
        {
          expression = "object.spec.type == 'ClusterIP' && !has(object.spec.loadBalancerClass) && !has(object.spec.externalName) && (!has(object.spec.externalIPs) || size(object.spec.externalIPs) == 0)"
          message    = "Satellite Services must use ClusterIP without external addresses or a load balancer class."
        },
        {
          expression = "!has(object.metadata.annotations) || object.metadata.annotations.all(key, !key.startsWith('tailscale.com/') && !key.startsWith('external-dns.kubernetes.io/') && !key.startsWith('external-dns.alpha.kubernetes.io/'))"
          message    = "Satellite Services cannot configure Tailscale exposure or ExternalDNS."
        }
      ]
    }
  }
}

resource "kubectl_manifest" "satellite_admission_policy" {
  for_each = local.satellite_admission_rules

  yaml_body = yamlencode({
    apiVersion = "admissionregistration.k8s.io/v1"
    kind       = "ValidatingAdmissionPolicy"
    metadata   = { name = "unicorns-satellite-${each.key}" }
    spec = {
      failurePolicy = "Fail"
      matchConstraints = {
        resourceRules = [{
          apiGroups   = each.value.apiGroups
          apiVersions = ["v1"]
          operations  = ["CREATE", "UPDATE"]
          resources   = each.value.resources
          scope       = "Namespaced"
        }]
      }
      validations = each.value.validations
    }
  })
}

resource "kubectl_manifest" "satellite_admission_binding" {
  for_each = local.satellite_admission_rules

  yaml_body = yamlencode({
    apiVersion = "admissionregistration.k8s.io/v1"
    kind       = "ValidatingAdmissionPolicyBinding"
    metadata   = { name = "unicorns-satellite-${each.key}" }
    spec = {
      policyName        = "unicorns-satellite-${each.key}"
      validationActions = ["Deny"]
      matchResources = {
        namespaceSelector = {
          matchLabels = { "unicorns.dev/satellite" = "true" }
        }
      }
    }
  })

  depends_on = [kubectl_manifest.satellite_admission_policy]
}
