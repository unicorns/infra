#!/usr/bin/env python3

from pathlib import Path

SCRIPT_PATH = Path(__file__)

from common.cli_utils import get_app
from common.provisioner_utils import init_environment, run_terraform
from common.variables import (GITHUB_ACTIONS_UNICORNS_INFRA_JWT_ROLE_NAME_RO,
                              GITHUB_ACTIONS_UNICORNS_INFRA_JWT_ROLE_NAME_RW,
                              HASHICORP_VAULT_ADDR)

app = get_app()

@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True)

    tf_vars = {
        "vault_address": HASHICORP_VAULT_ADDR,
        "github_actions_unicorns_infra_jwt_role_name_ro": GITHUB_ACTIONS_UNICORNS_INFRA_JWT_ROLE_NAME_RO,
        "github_actions_unicorns_infra_jwt_role_name_rw": GITHUB_ACTIONS_UNICORNS_INFRA_JWT_ROLE_NAME_RW,
    }

    run_terraform(tools, tf_vars)

if __name__ == "__main__":
    app()
