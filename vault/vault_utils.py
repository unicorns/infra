import os
import sys
from getpass import getpass
from pathlib import Path

import hvac

SCRIPT_PATH = Path(__file__)
BASE_DIR = SCRIPT_PATH.parent.parent
if str(BASE_DIR) not in sys.path:
    sys.path.append(str(BASE_DIR))

from common.cli_utils import get_app, TyperOutputFormat

DEFAULT_VAULT_ADDR = "http://localhost:8200"

state = {}

def mycallback(
    output_format: TyperOutputFormat = TyperOutputFormat.yaml,
    vault_addr: str = DEFAULT_VAULT_ADDR,
    token: str = None,
):
    state['output_format'] = output_format
    state['vault_addr'] = vault_addr
    state['token'] = token

app = get_app(callback_fn=mycallback)

@app.command()
def get_vault_addr(vault_addr: str = None):
    """
    Get the Vault address from various sources.
    """

    if vault_addr:
        return vault_addr

    if state.get('vault_addr'):
        return state['vault_addr']
    
    if os.environ.get('VAULT_ADDR'):
        return os.environ['VAULT_ADDR']
    
    return DEFAULT_VAULT_ADDR

@app.command()
def get_token(token: str = None):
    """
    Get the Vault token from various sources.
    """

    if token:
        return token

    if state.get('token'):
        return state['token']
    
    if os.environ.get('VAULT_TOKEN'):
        return os.environ['VAULT_TOKEN']
    
    return getpass("Please enter your Vault token (will be hidden): ")

@app.command()
def unseal(keys: list[str]):
    vault_addr = get_vault_addr()

    client = hvac.Client(url=vault_addr)
    for key in keys:
        client.sys.submit_unseal_key(key=key)
    
    return {
        "is_sealed": client.sys.is_sealed(),
    }

@app.command()
def seal():
    client = get_vault_client()
    client.sys.seal()

    return {
        "is_sealed": client.sys.is_sealed(),
    }

@app.command()
def snapshot(dest: str):
    client = get_vault_client()

    print(client.is_authenticated())

    res = client.sys.take_raft_snapshot()

    assert res.status_code == 200, f"Failed to take snapshot: {res.text}"

    with open(dest, 'wb') as f:
        f.write(res.content)

    print(f"Snapshot saved to {dest}")

def get_vault_client(vault_addr: str = None, token: str = None):
    vault_addr = get_vault_addr(vault_addr)
    token = get_token(token)

    client = hvac.Client(url=vault_addr, token=token)
    assert client.is_authenticated(), f"Failed to authenticate to Vault at {vault_addr}"

    return client

@app.command()
def list_secrets(path="/"):
    client = get_vault_client()
    secrets = client.secrets.kv.v2.list_secrets(path=path)['data']['keys']

    return secrets

@app.command()
def get_secret(path, key=""):
    client = get_vault_client()
    secret = client.secrets.kv.v2.read_secret(path=path)['data']['data']

    if key:
        secret = secret[key]

    return secret

if __name__ == "__main__":
    app()