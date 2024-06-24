#!/usr/bin/env python3

from pathlib import Path

SCRIPT_PATH = Path(__file__)

from common.cli_utils import get_app
from common.provisioner_utils import init_environment, run_terraform
from common.variables import HASHICORP_VAULT_ADDR

app = get_app()


@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True)

    usernames = tools.vault_client.secrets.kv.v2.list_secrets(path="/", mount_point="users")["data"]["keys"]
    users = [
        {
            "username": username,
            "policy_names": ["base-user"], # Policies are provisioned by the vault provisioner
            **tools.vault_client.secrets.kv.v2.read_secret(path=username, mount_point="users")["data"]["data"]
        }
        for username in usernames
    ]

    tf_vars = {
        "vault_address": HASHICORP_VAULT_ADDR,
        "users": users,
    }

    run_terraform(tools, tf_vars)


if __name__ == "__main__":
    app()
