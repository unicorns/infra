#!/usr/bin/env python3

from pathlib import Path

from common.provisioner_utils import ProvisionerTools, make_terragrunt_app
from common.utils import get_env_value

SCRIPT_PATH = Path(__file__)


def write_kubeconfig(tools: ProvisionerTools, kubeconfig: str):
    kube_config_path = tools.env.PROV_RUN_DIR / "kubeconfig"
    with open(kube_config_path, "w") as f:
        f.write(kubeconfig)

    return str(kube_config_path)


def resolve_kubeconfig_path(value: str):
    path = Path(value).expanduser().resolve()
    if not path.is_file():
        raise RuntimeError(f"Kubeconfig file does not exist: {path}")

    return str(path)


def require_var(name: str, value: str | None, hint: str):
    if value:
        return value

    raise RuntimeError(f"Missing {name}. {hint}")


def get_vars(tools: ProvisionerTools):
    kube_config_path = get_env_value("KUBE_CONFIG_PATH", "KUBECONFIG")
    if kube_config_path:
        kube_config_path = resolve_kubeconfig_path(kube_config_path)
    else:
        kubeconfig = get_env_value("KUBE_CONFIG")
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
            get_env_value("AKS_CLUSTER_NAME"),
            "Set AKS_CLUSTER_NAME or run the Azure provisioner first.",
        ),
        "key_vault_name": require_var(
            "key_vault_name",
            get_env_value("AZURE_KEY_VAULT_NAME", "KEY_VAULT_NAME"),
            "Set AZURE_KEY_VAULT_NAME or run the Azure provisioner first.",
        ),
        "key_vault_tenant_id": require_var(
            "key_vault_tenant_id",
            get_env_value("AZURE_TENANT_ID", "KEY_VAULT_TENANT_ID"),
            "Set AZURE_TENANT_ID or run the Azure provisioner first.",
        ),
        "key_vault_secret_provider_client_id": require_var(
            "key_vault_secret_provider_client_id",
            get_env_value("KEY_VAULT_SECRET_PROVIDER_CLIENT_ID"),
            "Set KEY_VAULT_SECRET_PROVIDER_CLIENT_ID or run the Azure provisioner first.",
        ),
        "ingress_external_ip": get_env_value(
            "INGRESS_EXTERNAL_IP",
            "AKS_INGRESS_EXTERNAL_IP",
            "GATE_CONTROLLER_ORIGIN_IP",
        ),
    }


app = make_terragrunt_app(SCRIPT_PATH, __package__, get_vars, use_vault=False)

if __name__ == "__main__":
    app()
