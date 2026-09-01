#!/usr/bin/env python3

import os
import subprocess
from pathlib import Path

from common.cli_utils import get_app
from common.provisioner_utils import (
    get_terraform_output,
    init_environment,
    run_terraform,
)
from common.utils import get_env_value

SCRIPT_PATH = Path(__file__)
OUTPUTS_DIR = SCRIPT_PATH.parent.parent / "outputs"
KUBECONFIG_PATH = OUTPUTS_DIR / "unicorns-aks-kubeconfig"
ENV_PATH = OUTPUTS_DIR / "azure.env"

app = get_app()

ENV_TF_VARS = {
    "subscription_id": ("ARM_SUBSCRIPTION_ID", "AZURE_SUBSCRIPTION_ID"),
    "app_client_id": ("ARM_CLIENT_ID", "AZURE_CLIENT_ID"),
    "app_tenant_id": ("ARM_TENANT_ID", "AZURE_TENANT_ID"),
    "app_client_secret": ("ARM_CLIENT_SECRET", "AZURE_CLIENT_SECRET"),
    "terraform_cloud_token": ("TF_TOKEN_app_terraform_io",),
}

AKS_ADMIN_GROUP_ENV = "AZURE_AKS_ADMIN_GROUP_OBJECT_IDS"


def get_tf_vars():
    variables = {
        tf_name: value
        for tf_name, env_names in ENV_TF_VARS.items()
        if (value := get_env_value(*env_names))
    }

    missing = [name for name in ENV_TF_VARS if name not in variables]
    if missing:
        required = ["/".join(ENV_TF_VARS[name]) for name in missing]
        raise RuntimeError(
            "Missing required Azure credentials: " + ", ".join(required)
        )

    admin_ids = get_env_value(AKS_ADMIN_GROUP_ENV)
    if not admin_ids:
        raise RuntimeError(f"Missing required AKS administrator groups: {AKS_ADMIN_GROUP_ENV}")

    admin_group_ids = [
        object_id.strip()
        for object_id in admin_ids.split(",")
        if object_id.strip()
    ]
    if not admin_group_ids:
        raise RuntimeError(
            f"Missing required AKS administrator groups: {AKS_ADMIN_GROUP_ENV}"
        )

    variables["aks_admin_group_object_ids"] = admin_group_ids

    if admin_ids := get_env_value(
        "AZURE_KEY_VAULT_ADMIN_OBJECT_IDS",
        "KEY_VAULT_ADMIN_OBJECT_IDS",
    ):
        variables["key_vault_admin_object_ids"] = [
            object_id.strip()
            for object_id in admin_ids.split(",")
            if object_id.strip()
        ]

    return variables


def require_output(outputs: dict, name: str):
    output = outputs.get(name)
    if not isinstance(output, dict) or output.get("value") in (None, ""):
        raise RuntimeError(f"Missing required Azure Terraform output: {name}")

    return output["value"]


def write_stack_outputs(outputs: dict):
    client_id = get_env_value("ARM_CLIENT_ID", "AZURE_CLIENT_ID")
    tenant_id = get_env_value("ARM_TENANT_ID", "AZURE_TENANT_ID")
    if not client_id or not tenant_id:
        raise RuntimeError("Missing Azure client or tenant ID for AKS kubeconfig")

    values = {
        "AKS_CLUSTER_NAME": require_output(outputs, "aks_cluster_name"),
        "INGRESS_EXTERNAL_IP": require_output(outputs, "ingress_static_ip"),
        "KUBE_CONFIG_PATH": str(KUBECONFIG_PATH.resolve()),
    }
    kubeconfig = require_output(outputs, "aks_kube_config")

    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    KUBECONFIG_PATH.write_text(kubeconfig)
    subprocess.run(
        [
            "kubelogin",
            "convert-kubeconfig",
            "--kubeconfig",
            str(KUBECONFIG_PATH),
            "--login",
            "spn",
            "--client-id",
            client_id,
            "--tenant-id",
            tenant_id,
        ],
        check=True,
    )
    output_owner = OUTPUTS_DIR.stat()
    os.chown(KUBECONFIG_PATH, output_owner.st_uid, output_owner.st_gid)
    KUBECONFIG_PATH.chmod(0o600)
    ENV_PATH.write_text(
        "".join(f"{name}={value}\n" for name, value in values.items())
    )


@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True)
    run_terraform(tools, get_tf_vars())
    write_stack_outputs(get_terraform_output(tools.env))


if __name__ == "__main__":
    app()
