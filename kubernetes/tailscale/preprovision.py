from common.provisioner_utils import ProvisionerTools
from common.variables import TAILSCALE_KUBERNETES_OPERATOR_SECRETS_PATH

def get_vars(tools: ProvisionerTools, project: str):
    tailscale_operator_secret = tools.vault_client.secrets.kv.v2.read_secret(
        TAILSCALE_KUBERNETES_OPERATOR_SECRETS_PATH
    )["data"]["data"]

    return {
        'tailscale_operator_client_id': tailscale_operator_secret["oauth_client_id"],
        'tailscale_operator_client_secret': tailscale_operator_secret["oauth_client_secret"],
    }
