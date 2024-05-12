#!/bin/bash

# This script starts a local vault server from a backup file. The backup file is a snapshot of the vault data.
# https://developer.hashicorp.com/vault/tutorials/standard-procedures/sop-backup
# This is useful for testing and disaster recovery scenarios.
#
# References:
# - https://developer.hashicorp.com/vault/tutorials/standard-procedures/sop-restore

set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

__backup_file=${1:-}
if [ -z "${__backup_file}" ]; then
  echo "Usage: start-local-vault-from-backup.sh <backup-file>"
  exit 1
fi

if [ ! -f "${__backup_file}" ]; then
  echo "Backup file not found: '${__backup_file}'"
  exit 1
fi

# Must match the path in the config file (local-vault.hcl)
rm -rf /tmp/vault-data
mkdir /tmp/vault-data

# Start a local vault server
echo "Starting vault server with backup '${__backup_file}'..."
vault server -config=${SCRIPT_DIR}/local-vault.hcl > /tmp/vault.log 2>&1 &
__vault_pid=$!

export VAULT_ADDR='http://127.0.0.1:8200'

# Wait for the server to start
sleep 5

echo "Initializing vault..."

# Initialize the vault
__tmp_vault_info=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)

# Unseal the vault
__unseal_key=$(echo "${__tmp_vault_info}" | jq -r '.unseal_keys_b64[0]')
vault operator unseal ${__unseal_key}

# Log into the vault
__root_token=$(echo "${__tmp_vault_info}" | jq -r '.root_token')
vault login ${__root_token}

echo "Restoring backup '${__backup_file}'..."

# Restore the backup
vault operator raft snapshot restore -force ${__backup_file}

# Wait for the server to start
sleep 5

echo "Vault server started with backup '${__backup_file}' at PID ${__vault_pid}. Logs are in /tmp/vault.log."
echo "Remember to:"
echo "  unseal the vault: 'python3 vault/vault_utils.py unseal <unseal-key1> <unseal-key2> ...'"



