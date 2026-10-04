# Shared AKS Stack

## Ownership boundary

This repository owns the shared platform: AKS, node pools, public Traefik,
private Traefik over Tailscale, wildcard DNS and certificate renewal, monitoring,
the Secrets Store CSI add-on, the shared Key Vault, and the static public ingress
IP. Application repositories own their namespace-level workloads and CI/CD
pipelines.

Application access uses Microsoft Entra authentication and namespace-scoped
Kubernetes RBAC. Local AKS accounts are disabled. Never give an application
pipeline the cluster administrator kubeconfig.

## Cost guardrails

The stack limits its fixed Azure footprint to:

- one `Standard_B2s` system node
- one shared Standard Load Balancer and static public ingress IP
- two optional ARM Spot pools with `min_count = 0` and a
  `0.02 USD/hour` maximum price per node
- one `32 GB` managed OS disk per active node
- one `1 GiB` managed disk for the private gateway's ACME certificate state
- Log Analytics capped at `0.25 GB/day`

The shared ingress and cluster should be reused for applications.
Application-specific databases, disks, traffic, and log volume add to this
baseline.

The autoscaler prefers `appspot` (`Standard_D2ps_v6`, at most two nodes), then
`appspotalt` (`Standard_D2ps_v5`, at most one node). Both sizes have two cores
and 8 GB RAM. Empty pools can scale to zero. Alternate capacity remains in use
while needed; applications are not restarted just to change VM generations.
User application pools carry `unicorns.dev/workload=applications`.
Applications select this label, so Spot shortages cannot move them onto the
system node. Spot capacity can be unavailable for both sizes.

Subscription-wide cost anomalies and billing-profile budgets provide native
spend and credit-runway alerts. See [Azure billing alerts](azure-billing-alerts.md).

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
   export PRIVATE_INGRESS_ACME_EMAIL="..."
   export CLOUDFLARE_ZONE_ID="..."
   export CLOUDFLARE_API_TOKEN="..."
   export TAILSCALE_CLIENT_ID="..."
   export TAILSCALE_AUDIENCE="..."
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

## Private ingress

Register the operator with a temporary administrator API token saved in a
local file with mode `0600`. Run one platform bootstrap at a time:

```sh
python3 kubernetes-shared/bootstrap-private-ingress.py \
  --api-token-file <token-file> \
  --subscription "$ARM_SUBSCRIPTION_ID" \
  --tailnet <connected-tailnet-name>
```

Store the returned `TAILSCALE_CLIENT_ID` and `TAILSCALE_AUDIENCE` as GitHub
repository variables. They are not secrets. The helper verifies the connected
tailnet and AKS resource, checks current-device access, and validates CI denial
tests before updating policy. It replaces the default allow-all source with
members, shared users, and declared machine tags excluding CI. New machine tags
need an explicit access grant. Other policy rules, SSH settings, and node
attributes are preserved. Revoke the temporary token after registrations.

The private platform uses three pods: the Tailscale operator, one shared
Tailscale proxy, and one Traefik gateway. The operator authenticates through
its Kubernetes ServiceAccount's workload identity. The gateway exposes only
TCP 443 through Tailscale, with no public load balancer or node ports.

Terraform protects the gateway Service, the DNS-only wildcard record, and the
certificate volume against deletion. The wildcard's address comes from the
actual Service status and must be exactly one Tailscale IPv4 address. Named
public records retain precedence over the wildcard.

Traefik renews `*.benzhang.dev` with Cloudflare DNS challenges and stores the
ACME account and certificates on its volume. Its single replica uses Recreate
updates so only one process writes that state. Gateway or proxy restarts can
briefly interrupt private requests.

Proxy and node replacements retain the Tailscale Service address. Deleting
the Kubernetes gateway Service also deletes its tailnet Service. If a Service
is deleted outside Terraform, reapply infrastructure to recreate it and update
the wildcard to its replacement address. DNS has a 60-second TTL.

## Application onboarding

Public and private applications use separate Traefik gateways and explicit
Ingress classes: `public` and `tailnet`. Both use the same pinned chart and
image versions. Neither class is the cluster default.

The public gateway is stateless and uses the platform's static Azure ingress
IP. Cloudflare provides browser-facing HTTPS. The origin accepts HTTP and
HTTPS, with no HTTP-to-HTTPS redirect. Only Cloudflare addresses are trusted
for forwarded headers, and local load-balancer traffic preserves those source
addresses. The platform sets a 180-second request-read and response-header
allowance. Applications require no gateway-specific annotations.

Each application needs a one-time platform registration:

- a namespace labeled `unicorns.dev/satellite=true`;
- a Microsoft Entra deployment identity federated to its protected GitHub
  environment;
- the AKS Cluster User role so it can retrieve a user kubeconfig; and
- a Kubernetes RoleBinding that grants only the resources required in that
  namespace.

Applications should use a dedicated Key Vault and AKS workload identity for
runtime secrets. Secret values must not pass through GitHub Actions.

Follow [Deploy a satellite application](satellite-app-deployment.md) for the
one-time permission setup and application-owned release procedure.
