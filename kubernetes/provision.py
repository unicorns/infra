#!/usr/bin/env python3

from pathlib import Path

SCRIPT_PATH = Path(__file__)

from common.provisioner_utils import ProvisionerTools, make_terragrunt_app


def get_vars(tools: ProvisionerTools):
    kubernetes_cluster_name = tools.vault_client.secrets.kv.v2.read_secret(path="outputs/azure")["data"]["data"]["aks1_cluster_name"]['value']
    kubeconfig = tools.vault_client.secrets.kv.v2.read_secret(path="outputs/azure")["data"]["data"]["aks1_kube_config"]["value"]
    with open(tools.env.PROV_RUN_DIR / "kubeconfig", "w") as f:
        f.write(kubeconfig)

    tf_vars = {
        'kube_config_path': str(tools.env.PROV_RUN_DIR / "kubeconfig"),
        'kubernetes_cluster_name': kubernetes_cluster_name,
    }

    return tf_vars


app = make_terragrunt_app(SCRIPT_PATH, __package__, get_vars)

if __name__ == "__main__":
    app()
