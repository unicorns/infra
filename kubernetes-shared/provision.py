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
        "ingress_external_ip": get_env_value(
            "INGRESS_EXTERNAL_IP",
            "AKS_INGRESS_EXTERNAL_IP",
        ),
    }


app = make_terragrunt_app(SCRIPT_PATH, get_vars)

if __name__ == "__main__":
    app()
