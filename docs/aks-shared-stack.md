# Shared AKS Stack

This is the replacement for the old `aks1` plus `aks2` layout.

## Cost guardrails

The target steady state is one shared AKS cluster:

- one always-on `Standard_B2s` system node
- one Standard Load Balancer shared by all ingress hosts
- one static Standard public IP for ingress
- one small managed OS disk
- one optional spot node pool with `min_count = 0` and a `0.02 USD/hour` max
  price
- Kubernetes `1.34.8`, the latest patch for the current West US 3 default minor
  at the time this runbook was written
- Azure Key Vault instead of self-hosted Vault
- Azure Monitor Container Insights with Log Analytics capped at `0.25 GB/day`
- no Elastic, Kibana, Fleet Server, or in-cluster Vault

The old two-cluster setup billed around `240-250 CAD/month` once both clusters
were running. This stack is intended to stay closer to `95-125 CAD/month` before
new app-specific storage or traffic, leaving room under a `2000 CAD/year` credit
budget. Raising the system node from `Standard_B2s` to `Standard_B2ps_v2` buys
more memory and should still be materially cheaper than two clusters, but it
reduces the monthly margin.

## Provision order

The provisioner now supports standard environment variables so the replacement
stack can be bootstrapped without the deleted self-hosted Vault.

The old `aks1` and `aks2` resources were removed from the active Azure
configuration. Because the clusters were deleted outside Terraform, the first
real Terraform Cloud plan may show cleanup for old state addresses such as:

```text
azurerm_resource_group.unicorns-aks1
azurerm_kubernetes_cluster.unicorns-aks1
azurerm_kubernetes_cluster_node_pool.aks1spot1
azurerm_kubernetes_cluster_node_pool.aks1spot4
azurerm_resource_group.unicorns-aks2
azurerm_kubernetes_cluster.unicorns-aks2
azurerm_kubernetes_cluster_node_pool.aks2spot1
```

Review that plan carefully before applying. If Terraform errors because Azure
already has no matching resource, remove only the stale old-cluster addresses
from Terraform Cloud state and rerun the plan.

1. Provide Terraform Cloud and Azure credentials.

   ```sh
   export TF_TOKEN_app_terraform_io="..."
   export ARM_SUBSCRIPTION_ID="..."
   export ARM_CLIENT_ID="..."
   export ARM_TENANT_ID="..."
   export ARM_CLIENT_SECRET="..."
   export AZURE_KEY_VAULT_ADMIN_OBJECT_IDS="$(az ad signed-in-user show --query id -o tsv)"
   ```

2. Review the Azure plan.

   ```sh
   DRY_RUN=1 docker compose run --rm provisioner ./azure/provision.py all
   ```

3. Apply Azure only after reviewing the plan.

   ```sh
   docker compose run --rm provisioner ./azure/provision.py all
   ```

4. Put gate-controller secrets in Azure Key Vault.

   ```sh
   az keyvault secret set \
     --vault-name unicornsftw-kv \
     --name gate-controller-cloud-v3-initial-admin-credentials \
     --value '{"username":"admin","password":"replace-this"}'

   az keyvault secret set \
     --vault-name unicornsftw-kv \
     --name gate-controller-cloud-v3-agent-token \
     --value 'replace-this'

   az keyvault secret set \
     --vault-name unicornsftw-kv \
     --name gate-controller-cloud-v3-openai-api-key \
     --value 'replace-this'
   ```

5. Fetch kubeconfig into the repo `outputs` directory.

   ```sh
   mkdir -p outputs
   az aks get-credentials \
     --resource-group unicorns-aks-rg \
     --name unicorns-aks \
     --file ./outputs/unicorns-aks-kubeconfig \
     --overwrite-existing
   ```

6. Export Kubernetes stack inputs.

   ```sh
   export KUBE_CONFIG_PATH=./outputs/unicorns-aks-kubeconfig
   export AKS_CLUSTER_NAME=unicorns-aks
   export AZURE_KEY_VAULT_NAME=unicornsftw-kv
   export AZURE_TENANT_ID="$(az account show --query tenantId -o tsv)"
   export KEY_VAULT_SECRET_PROVIDER_CLIENT_ID="$(
     az aks show \
       --resource-group unicorns-aks-rg \
       --name unicorns-aks \
       --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId \
       -o tsv
   )"
   export INGRESS_EXTERNAL_IP="$(
     terraform -chdir=azure output -raw ingress_static_ip
   )"
   ```

7. Review and apply the Kubernetes stack.

   ```sh
   DRY_RUN=1 docker compose run --rm provisioner ./kubernetes-shared/provision.py all
   docker compose run --rm provisioner ./kubernetes-shared/provision.py all
   ```

## DNS

After `kubernetes-shared/system` applies, the ingress service should use the
static Azure public IP from the Azure stack. Cloudflare is managed by the
`cloudflare` Terraform stack:

```sh
export CLOUDFLARE_API_TOKEN="..."
export GATE_CONTROLLER_ORIGIN_IP="$(terraform -chdir=azure output -raw ingress_static_ip)"

docker compose run --rm provisioner ./cloudflare/provision.py import-gate-controller
DRY_RUN=1 docker compose run --rm provisioner ./cloudflare/provision.py all
docker compose run --rm provisioner ./cloudflare/provision.py all
```

The `all` command also imports the existing A record automatically before a real
apply. Running the import command separately makes the first dry run reflect the
adopted record instead of showing a create.

## Notes

- Secret values are not managed by Terraform, so they do not land in Terraform
  state. Terraform manages the Key Vault, AKS access policy, and Kubernetes
  `SecretProviderClass`.
- The gate controller reads Key Vault secrets from mounted files at startup.
  After rotating a secret, restart the deployment:

  ```sh
  kubectl --kubeconfig ./outputs/unicorns-aks-kubeconfig \
    -n gate-controller-cloud-v3 rollout restart deployment/gate-controller-cloud-v3
  ```

- The gate controller uses one `ReadWriteOnce` PVC and deploys with `Recreate`
  strategy so SQLite has a single writer.
