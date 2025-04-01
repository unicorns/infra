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
    azure_spot_node_affinities = [
        {
            weight = 1
            preference = {
                matchExpressions = [
                    {
                        key      = "kubernetes.azure.com/scalesetpriority"
                        operator = "In"
                        values   = ["spot"]
                    }
                ]
            }
        }
    ]
}