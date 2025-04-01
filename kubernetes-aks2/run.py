#!/usr/bin/env python3

# This file sets up the kubeconfig file for accessing the kubernetes cluster.
# Example usage:
# python3 ./kubernetes/run.py -- k9s --all-namespaces
# python3 ./kubernetes/run.py -- kubectl get namespaces

import os
import subprocess
import tempfile

import typer

from vault.vault_utils import get_vault_client

app = typer.Typer()

@app.command()
def main(cmd_args: list[str]):
    vault_client = get_vault_client()
    kubeconfig = vault_client.secrets.kv.v2.read_secret(path="outputs/azure")["data"]["data"]["aks2_kube_config"]["value"]

    with tempfile.NamedTemporaryFile(mode="w") as f:
        f.write(kubeconfig)
        f.flush()

        print(f"Kubeconfig file written to {f.name}")

        os.environ["KUBECONFIG"] = f.name

        subprocess.run(cmd_args, check=True)

if __name__ == "__main__":
    app()