# Unicorns Infrastructure

This repository provisions the infrastructure for the gate controller:

- `azure`: one shared AKS cluster, Azure Key Vault, a static ingress IP, and
  capped Azure Monitor logs
- `cloudflare`: the public DNS record for the gate controller
- `kubernetes-shared`: ingress, kube-state-metrics, reloader, and the gate
  controller workload

Terraform Cloud stores state. Runtime application secrets live in Azure Key
Vault and are mounted into the gate-controller pod by the AKS Secrets Store CSI
driver. The T-RG spot VM is outside this repository's management boundary.

See [docs/aks-shared-stack.md](docs/aks-shared-stack.md) for provisioning and
operations.

## Provisioner

Build and open the provisioner container:

```sh
docker compose build provisioner
docker compose run --rm provisioner /bin/bash
```

Provisioners require `TF_TOKEN_app_terraform_io`. The Azure provisioner also
requires the four standard `ARM_*` service-principal variables, the Cloudflare
provisioner requires `CLOUDFLARE_API_TOKEN`, and the Kubernetes provisioner
requires `GATE_CONTROLLER_CLOUD_V3_IMAGE`.

Set `DRY_RUN` to run Terraform plans instead of applies. Set `NO_CONFIRM` to
pass automatic approval during an apply.

## Secrets

Set the gate-controller secrets directly in Azure Key Vault:

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
