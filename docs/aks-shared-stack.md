# Shared AKS Stack

## Cost guardrails

The stack limits its fixed Azure footprint to:

- one `Standard_B2s` system node
- one shared Standard Load Balancer and static public ingress IP
- one optional autoscaling spot pool with `min_count = 0` and a
  `0.02 USD/hour` maximum price
- one `32 GB` managed OS disk per active node
- Log Analytics capped at `0.25 GB/day`
- one `1 GiB` gate-controller data volume

The shared ingress and cluster should be reused for additional applications.
Application-specific databases, disks, traffic, and log volume add to this
baseline.

## Provisioning

1. Export credentials and required configuration.

   ```sh
   export TF_TOKEN_app_terraform_io="..."
   export ARM_SUBSCRIPTION_ID="..."
   export ARM_CLIENT_ID="..."
   export ARM_TENANT_ID="..."
   export ARM_CLIENT_SECRET="..."
   export AZURE_KEY_VAULT_ADMIN_OBJECT_IDS="$(az ad signed-in-user show --query id -o tsv)"
   export CLOUDFLARE_API_TOKEN="..."
   export GATE_CONTROLLER_CLOUD_V3_IMAGE="ghcr.io/ben-z/gate-controller/cloud-v3:sha-..."
   ```

2. Build the provisioner.

   ```sh
   docker compose build provisioner
   ```

3. Provision Azure and load its generated outputs.

   ```sh
   docker compose run --rm provisioner ./azure/provision.py all
   cat outputs/azure.env >> .env
   ```

   The Azure provisioner writes the AKS kubeconfig to
   `outputs/unicorns-aks-kubeconfig` and writes non-secret downstream values to
   `outputs/azure.env`.

4. Set the gate-controller secrets.

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

5. Provision DNS and Kubernetes.

   ```sh
   docker compose run --rm provisioner ./cloudflare/provision.py all
   docker compose run --rm provisioner ./kubernetes-shared/provision.py all
   ```

Set `DRY_RUN=1` before these commands to plan without applying changes. GitHub
Actions performs the same sequence and passes Azure's generated values directly
to the dependent provisioners.

## Operations

Terraform manages the Key Vault, its AKS access policy, and the Kubernetes
`SecretProviderClass`; secret values are not stored in Terraform state.

The gate controller reads mounted secrets at process startup. Restart the
deployment after rotating a secret:

```sh
kubectl --kubeconfig ./outputs/unicorns-aks-kubeconfig \
  -n gate-controller-cloud-v3 \
  rollout restart deployment/gate-controller-cloud-v3
```

The gate controller uses one `ReadWriteOnce` volume and a `Recreate` deployment
strategy so SQLite has a single writer.
