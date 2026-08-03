# Shared AKS Stack

## Ownership boundary

This repository owns the shared platform and application registration: AKS,
node pools, ingress-nginx, monitoring, the Secrets Store CSI add-on, shared and
application Key Vaults, identities, namespace access, deployment trust, and DNS.
Application repositories own their namespace-level workloads and CI/CD
pipelines.

Application access uses Microsoft Entra authentication and namespace-scoped
Kubernetes RBAC. Local AKS accounts are disabled. Never give an application
pipeline the cluster administrator kubeconfig.

## Cost guardrails

The stack limits its fixed Azure footprint to:

- one `Standard_B2s` system node
- one shared Standard Load Balancer and static public ingress IP
- one optional autoscaling spot pool with `min_count = 0` and a
  `0.02 USD/hour` maximum price
- one `32 GB` managed OS disk per active node
- Log Analytics capped at `0.25 GB/day`

The shared ingress and cluster should be reused for applications.
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
   export AZURE_KEY_VAULT_ADMIN_OBJECT_IDS="..."
   export AZURE_AKS_ADMIN_GROUP_OBJECT_IDS="..."
   ```

   Before the first Entra-enabled apply, create the AKS administrator group,
   bind the infrastructure service principal directly to Kubernetes
   `cluster-admin`, and set the GitHub Actions variable:

   ```sh
   ./azure/bootstrap-aks-entra.sh
   export AZURE_AKS_ADMIN_GROUP_OBJECT_IDS="$(az ad group show \
     --group unicorns-aks-admins --query id -o tsv)"
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

   The Azure provisioner writes an ignored AKS kubeconfig configured for
   non-interactive service-principal authentication. The provisioner image
   includes `kubelogin`; credentials remain in the `ARM_*` environment and are
   not embedded in the kubeconfig.

4. Provision shared Kubernetes services.

   ```sh
   docker compose run --rm provisioner ./kubernetes-shared/provision.py all
   ```

Set `DRY_RUN=1` before these commands to plan without applying changes. GitHub
Actions performs the same sequence.

## Application onboarding

Each application needs a one-time, infrastructure-owned platform registration:

- a namespace;
- a Microsoft Entra deployment identity federated to its protected GitHub
  environment;
- the AKS Cluster User role so it can retrieve a user kubeconfig; and
- a Kubernetes RoleBinding that grants only the resources required in that
  namespace.

Applications should use a dedicated Key Vault and AKS workload identity for
runtime secrets. Secret values must not pass through GitHub Actions.

Private registry credentials are the exception to declarative registration:
Terraform must not import them because provider state would retain the secret
data. Create and rotate the namespace pull Secret out of band, and let the
application reference its agreed name without granting its deployer access to
Kubernetes Secrets.

Follow [Deploy a satellite application](satellite-app-deployment.md) for the
one-time permission setup and application-owned release procedure.
