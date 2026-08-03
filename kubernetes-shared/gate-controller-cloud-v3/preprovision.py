import os
from urllib.parse import urlparse

from common.variables import GATE_CONTROLLER_CLOUD_V3_ADDR

DEFAULT_IMAGE = (
    "ghcr.io/ben-z/gate-controller/cloud-v3:"
    "sha-1c6098217042e3c0d685f982facbd1bc383b7132"
)


def get_vars(tools, project):
    return {
        "host": os.environ.get(
            "GATE_CONTROLLER_CLOUD_V3_HOST",
            urlparse(GATE_CONTROLLER_CLOUD_V3_ADDR).hostname,
        ),
        "image": os.environ.get("GATE_CONTROLLER_CLOUD_V3_IMAGE", DEFAULT_IMAGE),
    }
