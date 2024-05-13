from common.provisioner_utils import ProvisionerTools
from common.variables import KIBANA_ADDR
from urllib.parse import urlparse

def get_vars(tools: ProvisionerTools, project: str):
    return {
        'kibana_host': urlparse(KIBANA_ADDR).hostname,
    }
