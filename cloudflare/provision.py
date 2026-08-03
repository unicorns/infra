#!/usr/bin/env python3

from pathlib import Path

from common.cli_utils import get_app
from common.provisioner_utils import init_environment, run_terraform

SCRIPT_PATH = Path(__file__)

app = get_app()


@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True)
    run_terraform(tools, {})


if __name__ == "__main__":
    app()
