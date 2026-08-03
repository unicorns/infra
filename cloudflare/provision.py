#!/usr/bin/env python3

from pathlib import Path

from common.cli_utils import get_app
from common.provisioner_utils import init_environment, run_terraform
from common.utils import get_env_value

SCRIPT_PATH = Path(__file__)

app = get_app()


def get_tf_vars():
    token = get_env_value("CLOUDFLARE_API_TOKEN", "CF_API_TOKEN")
    if not token:
        raise RuntimeError("Missing CLOUDFLARE_API_TOKEN/CF_API_TOKEN.")

    return {"cloudflare_api_token": token}


@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True)
    run_terraform(tools, get_tf_vars())


if __name__ == "__main__":
    app()
