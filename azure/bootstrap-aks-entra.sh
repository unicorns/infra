#!/usr/bin/env bash
set -euo pipefail

readonly AKS_ADMIN_GROUP_NAME="unicorns-aks-admins"
readonly AZURE_RESOURCE_GROUP="unicorns-aks-rg"
readonly AZURE_AKS_CLUSTER_NAME="unicorns-aks"
readonly GITHUB_REPOSITORY="unicorns/infra"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

for task_command in az gh sed; do
  if ! command -v "$task_command" >/dev/null 2>&1; then
    echo "Missing required command: $task_command" >&2
    exit 1
  fi
done

if [[ -z "${ARM_CLIENT_ID:-}" ]]; then
  echo "Missing ARM_CLIENT_ID for the infrastructure service principal." >&2
  exit 1
fi

task_repo_admin="$(gh api "repos/$GITHUB_REPOSITORY" --jq '.permissions.admin')"
if [[ "$task_repo_admin" != "true" ]]; then
  echo "GitHub authentication must have administrator access to $GITHUB_REPOSITORY." >&2
  exit 1
fi

task_operator_id="$(az ad signed-in-user show --query id -o tsv)"
task_provisioner_id="$(az ad sp show --id "$ARM_CLIENT_ID" --query id -o tsv)"
task_group_count="$(az ad group list \
  --filter "displayName eq '$AKS_ADMIN_GROUP_NAME'" \
  --query 'length(@)' \
  -o tsv)"

if [[ "$task_group_count" -gt 1 ]]; then
  echo "More than one Microsoft Entra group is named $AKS_ADMIN_GROUP_NAME." >&2
  exit 1
fi

if [[ "$task_group_count" -eq 0 ]]; then
  task_group_id="$(az ad group create \
    --display-name "$AKS_ADMIN_GROUP_NAME" \
    --mail-nickname "$AKS_ADMIN_GROUP_NAME" \
    --query id \
    -o tsv)"
else
  task_group_id="$(az ad group list \
    --filter "displayName eq '$AKS_ADMIN_GROUP_NAME'" \
    --query '[0].id' \
    -o tsv)"
fi

task_operator_is_member="$(az ad group member check \
  --group "$task_group_id" \
  --member-id "$task_operator_id" \
  --query value \
  -o tsv)"
if [[ "$task_operator_is_member" != "true" ]]; then
  az ad group member add \
    --group "$task_group_id" \
    --member-id "$task_operator_id"
fi

task_temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unicorns-aks-entra.XXXXXX")"
task_rbac="$task_temp_dir/aks-provisioner-rbac.yaml"
cleanup() {
  unlink -- "$task_rbac" 2>/dev/null || true
  rmdir -- "$task_temp_dir" 2>/dev/null || true
}
trap cleanup EXIT

sed "s/__PROVISIONER_PRINCIPAL_ID__/$task_provisioner_id/g" \
  "$SCRIPT_DIR/aks-provisioner-rbac.yaml" > "$task_rbac"

task_rbac_exit_code="$(az aks command invoke \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_AKS_CLUSTER_NAME" \
  --command 'kubectl apply -f aks-provisioner-rbac.yaml' \
  --file "$task_rbac" \
  --query exitCode \
  -o tsv)"
if [[ "$task_rbac_exit_code" != "0" ]]; then
  echo "Failed to configure Kubernetes access for the infrastructure service principal." >&2
  exit 1
fi

gh variable set AZURE_AKS_ADMIN_GROUP_OBJECT_IDS \
  --repo "$GITHUB_REPOSITORY" \
  --body "$task_group_id"

echo "Configured AKS administrator group and infrastructure RBAC: $task_group_id"
