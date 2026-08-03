#!/usr/bin/env python3

from pathlib import Path

import rjsonnet
import json

from common.cli_utils import TyperOutputFormat, get_app

PROVISION_JOBS = [
    {
        "name": "Provision infrastructure",
        "command": "\n".join(
            [
                "docker compose run --rm provisioner ./azure/provision.py all",
                "cat outputs/azure.env >> .env",
                "docker compose run --rm provisioner ./cloudflare/provision.py all",
                "docker compose run --rm provisioner ./kubernetes-shared/provision.py all",
                "git diff --exit-code",
            ]
        ),
        "env": {
            "TF_TOKEN_app_terraform_io": "${{ secrets.TF_TOKEN_APP_TERRAFORM_IO }}",
            "ARM_SUBSCRIPTION_ID": "${{ secrets.ARM_SUBSCRIPTION_ID }}",
            "ARM_CLIENT_ID": "${{ secrets.ARM_CLIENT_ID }}",
            "ARM_TENANT_ID": "${{ secrets.ARM_TENANT_ID }}",
            "ARM_CLIENT_SECRET": "${{ secrets.ARM_CLIENT_SECRET }}",
            "AZURE_KEY_VAULT_ADMIN_OBJECT_IDS": "${{ vars.AZURE_KEY_VAULT_ADMIN_OBJECT_IDS }}",
            "AZURE_AKS_ADMIN_GROUP_OBJECT_IDS": "${{ vars.AZURE_AKS_ADMIN_GROUP_OBJECT_IDS }}",
            "CLOUDFLARE_API_TOKEN": "${{ secrets.CLOUDFLARE_API_TOKEN }}",
        },
    },
]

app = get_app(default_output_format=TyperOutputFormat.raw)

@app.command()
def generate_provision_workflow(jsonnet_file: str):
    ret = rjsonnet.evaluate_file(
        str(jsonnet_file),
        preserve_order=True,
        tla_codes={
            "provision_jobs": json.dumps(PROVISION_JOBS)
        }
    )

    return ret

if __name__ == "__main__":
    app()
