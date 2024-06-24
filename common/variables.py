# All DNS records below are created manually to point to the cluster ingress IP.
HASHICORP_VAULT_ADDR = "https://vault.benzhang.dev"
ELASTICSEARCH_ADDR = "https://elasticsearch.benzhang.dev"
KIBANA_ADDR = "https://kibana.benzhang.dev"

# The secrets are obtained from:
# https://github.com/organizations/unicorns/settings/apps/infrastructure-provisioner
GITHUB_INFRASTRUCTURE_PROVISIONER_APP_SECRETS_PATH = "github/infrastructure-provisioner-app"

# Manually-created Microsoft Entra ID Enterprise Application (client_id, tenant_id, client_secret):
# https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/d3652031-0c86-43e4-9129-4e50111477aa/isMSAApp~/false
#
# The app is manually given the following subscription Permissions (https://portal.azure.com/#@unicorn.onmicrosoft.com/resource/subscriptions/da091416-7245-487a-a165-deb1cb35397e/users):
# - Contributor
#
# The client secret is manually generated here:
# https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/d3652031-0c86-43e4-9129-4e50111477aa/isMSAApp~/false
#
# Instructions:
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret
AZURE_TERRAFORM_PROVISIONER_APP_SECRETS_PATH = "azure/terraform-provisioner"

# Contains the Azure subscription ID.
# It is manually obtained from Azure portal:
# https://portal.azure.com/#@unicorn.onmicrosoft.com/resource/subscriptions/da091416-7245-487a-a165-deb1cb35397e/overview
AZURE_SECRETS_PATH = "azure"

# Contains the Terraform Cloud access token (app.terraform.io).
# This token is created as a user token in the Terraform Cloud UI:
# https://app.terraform.io/app/settings/tokens
TERRAFORM_CLOUD_SECRETS_PATH = "tfcloud"

# Contains the Tailscale OAuth client ID and client secret.
# This is obtained from the Tailscale admin console:
# https://login.tailscale.com/admin/settings/oauth
TAILSCALE_KUBERNETES_OPERATOR_SECRETS_PATH = "tailscale/kubernetes-operator"

# Used to authenticate the GitHub Actions to HashiCorp Vault.
GITHUB_ACTIONS_UNICORNS_INFRA_JWT_ROLE_NAME_RO = (
    "github-actions-unicorns-infra-provisioner-ro"
)
GITHUB_ACTIONS_UNICORNS_INFRA_JWT_ROLE_NAME_RW = (
    "github-actions-unicorns-infra-provisioner-rw"
)
