locals {
    # Attaching this toleration to pods will allow them to be scheduled on spot nodes
    azure_spot_node_tolerations = [
        {
            key      = "kubernetes.azure.com/scalesetpriority"
            operator = "Equal"
            value    = "spot"
            effect   = "NoSchedule"
        }
    ]
}