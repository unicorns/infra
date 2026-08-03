#!/usr/bin/env python3

from pathlib import Path

from common.cli_utils import get_app
from common.provisioner_utils import (
    init_environment,
    run_terraform,
)
from common.utils import get_env_value
from common.variables import (
    AZURE_TERRAFORM_PROVISIONER_APP_SECRETS_PATH,
    AZURE_SECRETS_PATH,
)

SCRIPT_PATH = Path(__file__)

app = get_app()

ENV_TF_VARS = {
    "subscription_id": ("ARM_SUBSCRIPTION_ID", "AZURE_SUBSCRIPTION_ID"),
    "app_client_id": ("ARM_CLIENT_ID", "AZURE_CLIENT_ID"),
    "app_tenant_id": ("ARM_TENANT_ID", "AZURE_TENANT_ID"),
    "app_client_secret": ("ARM_CLIENT_SECRET", "AZURE_CLIENT_SECRET"),
}


def get_env_tf_vars():
    tf_vars = {
        tf_name: value
        for tf_name, env_names in ENV_TF_VARS.items()
        if (value := get_env_value(*env_names))
    }

    if admin_ids := get_env_value(
        "AZURE_KEY_VAULT_ADMIN_OBJECT_IDS",
        "KEY_VAULT_ADMIN_OBJECT_IDS",
    ):
        tf_vars["key_vault_admin_object_ids"] = [
            object_id.strip()
            for object_id in admin_ids.split(",")
            if object_id.strip()
        ]

    return tf_vars


def get_vault_tf_vars(tools):
    app_secrets = tools.vault_client.secrets.kv.v2.read_secret(
        AZURE_TERRAFORM_PROVISIONER_APP_SECRETS_PATH
    )["data"]["data"]
    subscription_id = tools.vault_client.secrets.kv.v2.read_secret(
        AZURE_SECRETS_PATH
    )["data"]["data"]["subscription_id"]

    return {
        "subscription_id": subscription_id,
        "app_client_id": app_secrets["client_id"],
        "app_client_secret": app_secrets["client_secret"],
        "app_tenant_id": app_secrets["tenant_id"],
    }


@app.command()
def all():
    tf_vars = get_env_tf_vars()
    missing_credentials = [name for name in ENV_TF_VARS if name not in tf_vars]
    tools = init_environment(
        SCRIPT_PATH,
        use_terraform=True,
        use_vault=bool(missing_credentials),
    )

    if missing_credentials:
        vault_tf_vars = get_vault_tf_vars(tools)
        for name in missing_credentials:
            tf_vars[name] = vault_tf_vars[name]

    run_terraform(tools, tf_vars)


if __name__ == "__main__":
    app()
