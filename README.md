# Unicorns Infrastructure

This repository provisions the shared platform used by applications:

- `azure`: AKS, Azure Key Vault, a static ingress IP, and capped Azure Monitor logs
- `kubernetes-shared`: ingress-nginx, kube-state-metrics, and reloader

Terraform Cloud stores state. Application workloads, runtime configuration, and
release pipelines belong in their application repositories. This repository may
include examples, but it does not deploy personal applications.

See [docs/aks-shared-stack.md](docs/aks-shared-stack.md) for provisioning and
operations. See
[docs/satellite-app-deployment.md](docs/satellite-app-deployment.md) to onboard
and deploy an application from its own repository.

## Provisioner

Build and open the provisioner container:

```sh
docker compose build provisioner
docker compose run --rm provisioner /bin/bash
```

Provisioning requires `TF_TOKEN_app_terraform_io`, the four standard `ARM_*`
service-principal variables, `AZURE_KEY_VAULT_ADMIN_OBJECT_IDS`, and
`AZURE_AKS_ADMIN_GROUP_OBJECT_IDS`.

The AKS administrator variable must contain one or more comma-separated
Microsoft Entra group object IDs. Both human operators and the infrastructure
service principal must belong to one of those groups before local AKS accounts
are disabled.

Set `DRY_RUN` to run Terraform plans instead of applies. Set `NO_CONFIRM` to
pass automatic approval during an apply.
