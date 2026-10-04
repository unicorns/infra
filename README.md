# Unicorns Infrastructure

This repository provisions the shared platform used by applications:

- `azure`: AKS, Azure Key Vault, a static ingress IP, capped Azure Monitor logs,
  and billing-profile cost alerts
- `kubernetes-shared`: public Traefik, private Traefik over Tailscale,
  wildcard DNS and certificate renewal, satellite admission policies,
  kube-state-metrics, and reloader

Terraform Cloud stores state. Application workloads, runtime configuration, and
release pipelines belong in their application repositories. This repository may
include examples, but it does not deploy personal applications.

See [docs/aks-shared-stack.md](docs/aks-shared-stack.md) for provisioning and
operations. See
[docs/satellite-app-deployment.md](docs/satellite-app-deployment.md) to onboard
and deploy an application from its own repository. See
[docs/azure-billing-alerts.md](docs/azure-billing-alerts.md) for the native cost
guardrails and grant-renewal procedure.

## Provisioner

Build and open the provisioner container:

```sh
docker compose build provisioner
docker compose run --rm provisioner /bin/bash
```

Provisioning requires `TF_TOKEN_app_terraform_io`, the four standard `ARM_*`
service-principal variables, `AZURE_KEY_VAULT_ADMIN_OBJECT_IDS`, and
`AZURE_AKS_ADMIN_GROUP_OBJECT_IDS`.

Private ingress also requires `PRIVATE_INGRESS_ACME_EMAIL`,
`CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_API_TOKEN`, `TAILSCALE_CLIENT_ID`, and
`TAILSCALE_AUDIENCE`. The Tailscale values identify the operator's workload
identity registration. Cloudflare authentication uses the provider environment
and an out-of-band Kubernetes Secret; its token does not enter Terraform state.

The Azure stack also declaratively owns application-state workspaces in HCP
Terraform. The provisioner passes `TF_TOKEN_app_terraform_io` as a sensitive,
ephemeral provider input; the credential must be able to create and update
workspaces in the `unicornsftw` organization. It is never stored in Terraform
state or outputs.

The AKS administrator variable must contain one or more comma-separated
Microsoft Entra group object IDs. Both human operators and the infrastructure
service principal must belong to one of those groups before local AKS accounts
are disabled.

Set `DRY_RUN` to run Terraform plans instead of applies. Set `NO_CONFIRM` to
pass automatic approval during an apply.
