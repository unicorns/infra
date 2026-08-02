#!/usr/bin/env python3

from pathlib import Path

from common.provisioner_utils import ProvisionerTools, make_terragrunt_app
from common.utils import get_env_value

SCRIPT_PATH = Path(__file__)


def get_vault_outputs(tools: ProvisionerTools):
    if not tools.vault_client:
        return {}

    try:
        return tools.vault_client.secrets.kv.v2.read_secret(
            path="outputs/azure"
        )["data"]["data"]
    except Exception:
        return {}


def output_value(outputs: dict, name: str):
    return outputs.get(name, {}).get("value")


def write_kubeconfig(tools: ProvisionerTools, kubeconfig: str):
    kube_config_path = tools.env.PROV_RUN_DIR / "kubeconfig"
    with open(kube_config_path, "w") as f:
        f.write(kubeconfig)

    return str(kube_config_path)


def require_var(name: str, value: str | None, hint: str):
    if value:
        return value

    raise RuntimeError(f"Missing {name}. {hint}")


def get_vars(tools: ProvisionerTools):
    azure_outputs = get_vault_outputs(tools)

    kube_config_path = get_env_value("KUBE_CONFIG_PATH", "KUBECONFIG")
    if not kube_config_path:
        kubeconfig = get_env_value("KUBE_CONFIG")
        if not kubeconfig:
            kubeconfig = output_value(azure_outputs, "aks_kube_config")
        if kubeconfig:
            kube_config_path = write_kubeconfig(tools, kubeconfig)

    return {
        "kube_config_path": require_var(
            "kube_config_path",
            kube_config_path,
            "Set KUBE_CONFIG_PATH, KUBECONFIG, or KUBE_CONFIG.",
        ),
        "kubernetes_cluster_name": require_var(
            "kubernetes_cluster_name",
            get_env_value("AKS_CLUSTER_NAME")
            or output_value(azure_outputs, "aks_cluster_name"),
            "Set AKS_CLUSTER_NAME or run the Azure provisioner first.",
        ),
        "key_vault_name": require_var(
            "key_vault_name",
            get_env_value("AZURE_KEY_VAULT_NAME", "KEY_VAULT_NAME")
            or output_value(azure_outputs, "key_vault_name"),
            "Set AZURE_KEY_VAULT_NAME or run the Azure provisioner first.",
        ),
        "key_vault_tenant_id": require_var(
            "key_vault_tenant_id",
            get_env_value("AZURE_TENANT_ID", "KEY_VAULT_TENANT_ID")
            or output_value(azure_outputs, "key_vault_tenant_id"),
            "Set AZURE_TENANT_ID or run the Azure provisioner first.",
        ),
        "key_vault_secret_provider_client_id": require_var(
            "key_vault_secret_provider_client_id",
            get_env_value("KEY_VAULT_SECRET_PROVIDER_CLIENT_ID")
            or output_value(azure_outputs, "aks_key_vault_secret_provider_client_id"),
            "Set KEY_VAULT_SECRET_PROVIDER_CLIENT_ID or run the Azure provisioner first.",
        ),
        "ingress_external_ip": get_env_value(
            "INGRESS_EXTERNAL_IP",
            "AKS_INGRESS_EXTERNAL_IP",
            "GATE_CONTROLLER_ORIGIN_IP",
        )
        or output_value(azure_outputs, "ingress_static_ip"),
    }


app = make_terragrunt_app(SCRIPT_PATH, __package__, get_vars)

if __name__ == "__main__":
    app()
