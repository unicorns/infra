from common.provisioner_utils import ProvisionerTools
from common.variables import KIBANA_ADDR, ELASTICSEARCH_ADDR
from urllib.parse import urlparse

def get_vars(tools: ProvisionerTools, project: str):
    return {
        "elasticsearch_host": urlparse(ELASTICSEARCH_ADDR).hostname,
        "kibana_host": urlparse(KIBANA_ADDR).hostname,
    }
