# Infrastructure Configuration

```bash
git fetch \
&& docker compose build provisioner \
&& docker compose run --rm provisioner /bin/bash
```

## Architecture

This repository contains various provisioners. The provisioners depend on the following services:
- [Vault](https://vaultproject.io): For secrets management. This is self-hosted on Azure Kubernetes.
- [Terraform Cloud](https://app.terraform.io): For state management. This is managed by HashiCorp.

### TODOs

- [ ] Back up Terraform state
- [ ] Back up Vault data
