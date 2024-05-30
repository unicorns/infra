#!/usr/bin/env python3

from pathlib import Path

import rjsonnet
import json
import yaml
import sys

from common.cli_utils import get_app, TyperOutputFormat, JSONSetEncoder

app = get_app()

@app.command()
def generate_provision_workflow(jsonnet_file: str):
    ret = rjsonnet.evaluate_file(
        str(jsonnet_file),
        preserve_order=True,
        tla_codes={
            "provision_jobs": json.dumps([
                {
                    "name": "Provision GitHub",
                    "command": "docker compose run provisioner ./github/provision.py all",
                    "requires_vault": True,
                },
                {
                    "name": "Provision Kubernetes",
                    "command": "docker compose run provisioner ./kubernetes/provision.py all",
                    "requires_vault": True,
                }
            ])
        }
    )

    return ret

if __name__ == "__main__":
    app()
