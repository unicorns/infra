#!/usr/bin/env python3

import json
import os
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from common.cli_utils import get_app
from common.provisioner_utils import init_environment, run_terraform
from common.utils import get_env_value

SCRIPT_PATH = Path(__file__)
TERRAFORM_WORKSPACE_URL = (
    "https://app.terraform.io/api/v2/organizations/unicornsftw/workspaces/"
    "unicorns-application-pigeon-registration"
)

app = get_app()

ENV_TF_VARS = {
    "subscription_id": ("ARM_SUBSCRIPTION_ID", "AZURE_SUBSCRIPTION_ID"),
    "app_client_id": ("ARM_CLIENT_ID", "AZURE_CLIENT_ID"),
    "app_tenant_id": ("ARM_TENANT_ID", "AZURE_TENANT_ID"),
    "app_client_secret": ("ARM_CLIENT_SECRET", "AZURE_CLIENT_SECRET"),
    "kube_config_path": ("KUBE_CONFIG_PATH", "KUBECONFIG"),
    "github_token": ("PIGEON_GITHUB_ADMIN_TOKEN",),
    "cloudflare_api_token": ("CLOUDFLARE_API_TOKEN", "CF_API_TOKEN"),
}


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
            "Missing required Pigeon registration configuration: "
            + ", ".join(required)
        )

    kube_config_path = Path(variables["kube_config_path"]).expanduser().resolve()
    if not kube_config_path.is_file():
        raise RuntimeError(f"Kubeconfig file does not exist: {kube_config_path}")
    variables["kube_config_path"] = str(kube_config_path)

    admin_ids = get_env_value(
        "AZURE_KEY_VAULT_ADMIN_OBJECT_IDS",
        "KEY_VAULT_ADMIN_OBJECT_IDS",
    )
    parsed_admin_ids = [
        object_id.strip()
        for object_id in (admin_ids or "").split(",")
        if object_id.strip()
    ]
    if len(parsed_admin_ids) != 1:
        raise RuntimeError(
            "Pigeon registration requires exactly one Azure Key Vault admin in "
            "AZURE_KEY_VAULT_ADMIN_OBJECT_IDS/KEY_VAULT_ADMIN_OBJECT_IDS."
        )
    variables["key_vault_admin_object_id"] = parsed_admin_ids[0]

    return variables


def require_local_terraform_workspace():
    token = os.environ.get("TF_TOKEN_app_terraform_io")
    if not token:
        raise RuntimeError("Missing TF_TOKEN_app_terraform_io.")
    request = Request(
        TERRAFORM_WORKSPACE_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/vnd.api+json",
        },
    )
    try:
        with urlopen(request, timeout=15) as response:
            payload = json.load(response)
    except HTTPError as error:
        if error.code == 404:
            raise RuntimeError(
                "Pigeon Terraform workspace is missing; apply the infra-owned "
                "workspace registration first."
            ) from error
        raise RuntimeError(
            f"Cannot inspect Pigeon Terraform workspace: HTTP {error.code}."
        ) from error
    except (URLError, TimeoutError, json.JSONDecodeError) as error:
        raise RuntimeError(
            f"Cannot inspect Pigeon Terraform workspace: {error}."
        ) from error

    attributes = payload.get("data", {}).get("attributes", {})
    if attributes.get("execution-mode") != "local":
        raise RuntimeError(
            "Pigeon Terraform workspace must use local execution before the "
            "runner-local Kubernetes provider can run."
        )


@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True)
    require_local_terraform_workspace()
    run_terraform(tools, get_tf_vars(), refresh_plan=True)


if __name__ == "__main__":
    app()
