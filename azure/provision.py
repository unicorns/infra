from pathlib import Path
import sys

SCRIPT_PATH = Path(__file__)
sys.path.append(str(SCRIPT_PATH.parent.parent))

from common.provisioner_utils import (
    init_environment,
    run_terraform,
)
from common.cli_utils import get_app

app = get_app()

@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True)

    app_secrets = tools.vault_client.secrets.kv.v2.read_secret('azure/terraform-provisioner')['data']['data']
    subscription_id = tools.vault_client.secrets.kv.v2.read_secret('azure')['data']['data']['subscription_id']

    tf_vars = {
        'subscription_id': subscription_id,
        'app_client_id': app_secrets['client_id'],
        'app_client_secret': app_secrets['client_secret'],
        'app_tenant_id': app_secrets['tenant_id'],
    }

    run_terraform(tools.env, tf_vars)


if __name__ == "__main__":
    app()
