from common.provisioner_utils import ProvisionerTools
from common.variables import GATE_CONTROLLER_CLOUD_V3_ADDR
from urllib.parse import urlparse

def get_vars(tools: ProvisionerTools, project: str):
    return {
        'host': urlparse(GATE_CONTROLLER_CLOUD_V3_ADDR).hostname,
        'initial_admin_credentials': tools.vault_client.secrets.kv.v2.read_secret(path=f"kubernetes/{project}")["data"]["data"]["initial_admin_credentials"]
    }
