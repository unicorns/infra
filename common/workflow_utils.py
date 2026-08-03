#!/usr/bin/env python3

from pathlib import Path

import rjsonnet
import json

from common.cli_utils import get_app

PROVISIONERS = {
    "azure": {
        "env": {
            "TF_TOKEN_app_terraform_io": "${{ secrets.TF_TOKEN_APP_TERRAFORM_IO }}",
            "ARM_SUBSCRIPTION_ID": "${{ secrets.ARM_SUBSCRIPTION_ID }}",
            "ARM_CLIENT_ID": "${{ secrets.ARM_CLIENT_ID }}",
            "ARM_TENANT_ID": "${{ secrets.ARM_TENANT_ID }}",
            "ARM_CLIENT_SECRET": "${{ secrets.ARM_CLIENT_SECRET }}",
            "AZURE_KEY_VAULT_ADMIN_OBJECT_IDS": "${{ vars.AZURE_KEY_VAULT_ADMIN_OBJECT_IDS }}",
        },
    },
    "cloudflare": {
        "dependencies": ["Provision azure"],
        "env": {
            "TF_TOKEN_app_terraform_io": "${{ secrets.TF_TOKEN_APP_TERRAFORM_IO }}",
            "CLOUDFLARE_API_TOKEN": "${{ secrets.CLOUDFLARE_API_TOKEN }}",
            "GATE_CONTROLLER_ORIGIN_IP": "${{ vars.INGRESS_EXTERNAL_IP }}",
        },
    },
    "kubernetes-shared": {
        "dependencies": ["Provision azure"],
        "env": {
            "TF_TOKEN_app_terraform_io": "${{ secrets.TF_TOKEN_APP_TERRAFORM_IO }}",
            "KUBE_CONFIG": "${{ secrets.KUBE_CONFIG }}",
            "AKS_CLUSTER_NAME": "${{ vars.AKS_CLUSTER_NAME }}",
            "AZURE_KEY_VAULT_NAME": "${{ vars.AZURE_KEY_VAULT_NAME }}",
            "AZURE_TENANT_ID": "${{ secrets.ARM_TENANT_ID }}",
            "KEY_VAULT_SECRET_PROVIDER_CLIENT_ID": "${{ vars.KEY_VAULT_SECRET_PROVIDER_CLIENT_ID }}",
            "INGRESS_EXTERNAL_IP": "${{ vars.INGRESS_EXTERNAL_IP }}",
        },
    },
}

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
                    **options,
                }
                for p, options in PROVISIONERS.items()
            ])
        }
    )

    return ret

if __name__ == "__main__":
    app()
