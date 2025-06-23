from common.provisioner_utils import ProvisionerTools
from common.variables import HASHICORP_VAULT_ADDR
from urllib.parse import urlparse

def get_vars(tools: ProvisionerTools, project: str):
    return {
        'vault_host': urlparse(HASHICORP_VAULT_ADDR).hostname,
    }
