#!/usr/bin/env python3

from pathlib import Path

SCRIPT_PATH = Path(__file__)

from common.cli_utils import get_app
from common.provisioner_utils import init_environment, run_terraform
from common.variables import GITHUB_INFRASTRUCTURE_PROVISIONER_APP_SECRETS_PATH
from github import Auth, GithubIntegration


app = get_app()

@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True)

    github_app_data = tools.vault_client.secrets.kv.v2.read_secret(GITHUB_INFRASTRUCTURE_PROVISIONER_APP_SECRETS_PATH)['data']['data']
    app_client_id = github_app_data['client_id']
    app_private_key = github_app_data['private_key']

    auth = Auth.AppAuth(app_client_id, app_private_key)
    gi = GithubIntegration(auth=auth)

    installations = gi.get_installations()
    try:
        installations[1]
    except IndexError:
        pass
    else:
        raise Exception("Multiple app installations found, please update the code to handle this case")

    installation_id = installations[0].id

    tf_vars = {
        "app_id": app_client_id,
        "installation_id": installation_id,
        "pem_file": app_private_key,
    }

    run_terraform(tools, tf_vars)

if __name__ == "__main__":
    app()
