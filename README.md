# Infrastructure Configuration

```bash
git fetch \
&& docker compose build provisioner \
&& docker compose run --rm provisioner /bin/bash
```

## Architecture

This repository contains various provisioners. The provisioners depend on the following services:
- [Azure Key Vault](https://azure.microsoft.com/products/key-vault): For runtime application secrets.
- [Terraform Cloud](https://app.terraform.io): For state management. This is managed by HashiCorp.

The current low-cost app hosting target is a single shared AKS cluster, Azure Key
Vault, and capped Azure Monitor logs. See [docs/aks-shared-stack.md](docs/aks-shared-stack.md).

## Provisioner environment variables

- `DRY_RUN`: If set to a non-empty value, provisioners will not apply changes. This is useful for testing. Default is empty (apply changes).
- `NO_CONFIRM`: If set to a non-empty value, provisioners will not ask for confirmation before applying changes. This is useful in CI. Default is empty (ask for confirmation).
- `BACK_UP_STATE`: If set to a non-empty value, supported provisioners will back up state files after applying changes. Default is empty (do not back up state files).

## Users

Users can be created by an administrator by adding a record into the `users` kv2 mount and then running the `users` provisioner.

## Secrets

Runtime application secrets live in Azure Key Vault. The shared AKS stack uses
the Azure Key Vault Secrets Store CSI add-on so pods can read secrets without
putting secret values in Terraform state.

To set the gate-controller secrets:

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

## Legacy Vault

The old stack hosted [HashiCorp Vault](https://www.vaultproject.io/) on AKS.
Those utilities remain for migration and state recovery, but new runtime app
secrets should use Azure Key Vault.

To put a secret into Vault:

```sh
./vault/vault_utils.py put-secret path/to/secret '{"mykey1": "mysecret1", "mykey2": "mysecret2"}'
```

To get a secret from Vault:

```sh
./vault/vault_utils.py --output-format=json get-secret path/to/secret 
# Output:
# {
#     "mykey1": "mysecret1",
#     "mykey2": "mysecret2"
# }
```

To get a specific key from a secret:

```sh
./vault/vault_utils.py --output-format=json get-secret path/to/secret --key mykey1
# Output:
# "mysecret1"
./vault/vault_utils.py --output-format=raw get-secret path/to/secret --key mykey1
# Output (raw, useful for using secrets in scripts):
# mysecret1
```

To delete a secret:

```sh
./vault/vault_utils.py delete-secret path/to/secret
```

If the Vault server restarts, we will need to unseal the server. This can be done by running:
```sh
./vault/vault_utils.py unseal <unseal-key1> [unseal-key2] [unseal-key3]
```

The vault is configured to require 3 unseal keys. They can be provided in different invocations of the command.
