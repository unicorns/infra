#!/usr/bin/env python3

from pathlib import Path

SCRIPT_PATH = Path(__file__)

from common.cli_utils import get_app
from common.provisioner_utils import init_environment, run_terraform

app = get_app()

@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True)

    elastic_password = tools.vault_client.secrets.kv.v2.read_secret(
        "outputs/kubernetes/elastic"
    )["data"]["data"]["es1_elastic_user_password"]['value']

    tf_vars = {
        "elastic_password": elastic_password,
    }

    run_terraform(tools, tf_vars)

if __name__ == "__main__":
    app()
