#!/usr/bin/env python3

from pathlib import Path

import rjsonnet
import json

from common.cli_utils import get_app

PROVISIONERS = sorted([p.parent.name for p in Path(__file__).parent.parent.glob("*/provision.py")])

app = get_app()

@app.command()
def generate_provision_workflow(jsonnet_file: str):
    ret = rjsonnet.evaluate_file(
        str(jsonnet_file),
        preserve_order=True,
        tla_codes={
            "provision_jobs": json.dumps([
                {
                    "name": f"Provision {p}",
                    "command": f"docker compose run provisioner ./{p}/provision.py all",
                    "requires_vault": True,
                } for p in PROVISIONERS
            ])
        }
    )

    return ret

if __name__ == "__main__":
    app()
