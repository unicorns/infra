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

## Provisioner environment variables

- `DRY_RUN`: If set to a non-empty value, provisioners will not apply changes. This is useful for testing. Default is empty (apply changes).
- `NO_CONFIRM`: If set to a non-empty value, provisioners will not ask for confirmation before applying changes. This is useful in CI. Default is empty (ask for confirmation).
- `BACK_UP_STATE`: If set to a non-empty value, supported provisioners will back up state files after applying changes. Default is empty (do not back up state files).