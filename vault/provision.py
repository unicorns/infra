#!/usr/bin/env python3

from pathlib import Path

SCRIPT_PATH = Path(__file__)

from common.provisioner_utils import (
    init_environment,
    run_terraform,
    get_terraform_output,
    update_output,
)
from common.cli_utils import get_app
from common.variables import HASHICORP_VAULT_ADDR

app = get_app()

@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True)

    tf_vars = {
        "vault_address": HASHICORP_VAULT_ADDR,
    }

    run_terraform(tools, tf_vars)

if __name__ == "__main__":
    app()
