#!/usr/bin/env python3

import json
import os
from getpass import getpass
from pathlib import Path

import hvac
import typer
from typing_extensions import Annotated

from common.cli_utils import TyperOutputFormat, get_app
from common.variables import HASHICORP_VAULT_ADDR

DEFAULT_VAULT_ADDR = HASHICORP_VAULT_ADDR
# This file is also used by the vault CLI to cache the token
VAULT_TOKEN_PATH = Path.home() / ".vault-token"

state = {}

def print_verbose(*args, **kwargs):
    if state.get("verbose"):
        print(*args, **kwargs)

def mycallback(
    output_format: TyperOutputFormat = TyperOutputFormat.yaml,
    vault_addr: str = None,
    token: str = None,
    verbose: bool = False,
):
    state['output_format'] = output_format
    state['vault_addr'] = vault_addr
    state['token'] = token
    state['verbose'] = verbose

app = get_app(callback_fn=mycallback)

@app.command()
def get_vault_addr(vault_addr: str = None):
    """
    Get the Vault address from various sources.
    """

    if vault_addr:
        print_verbose(f"Using Vault address from CLI: {vault_addr}")
        return vault_addr

    if state.get('vault_addr'):
        print_verbose(f"Using Vault address from state: {state['vault_addr']}")
        return state['vault_addr']
    
    if os.environ.get('VAULT_ADDR'):
        print_verbose(f"Using Vault address from environment: {os.environ['VAULT_ADDR']}")
        return os.environ['VAULT_ADDR']
    
    print_verbose(f"Using default Vault address: {DEFAULT_VAULT_ADDR}")
    return DEFAULT_VAULT_ADDR

@app.command()
def unseal(keys: list[str]):
    vault_addr = get_vault_addr()

    client = hvac.Client(url=vault_addr)
    client.sys.submit_unseal_keys(keys)
    
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

    client = hvac.Client(url=vault_addr)
    if not client.sys.is_initialized():
        raise Exception(f"Vault at {vault_addr} is not initialized. Please initialize it first.")
    if client.sys.is_sealed():
        raise Exception(f"Vault at {vault_addr} is sealed. Please unseal it first.")

    if token:
        print_verbose("token from args")
        client.token = token
        if client.is_authenticated():
            return client

    if state.get("token"):
        print_verbose("Trying token from CLI state")
        client.token = state["token"]
        if client.is_authenticated():
            return client

    if os.environ.get("VAULT_TOKEN"):
        print_verbose("Trying token from environment")
        client.token = os.environ["VAULT_TOKEN"]
        if client.is_authenticated():
            return client

    if VAULT_TOKEN_PATH.exists():
        print_verbose("Trying token from cache")
        client.token = VAULT_TOKEN_PATH.read_text()
        if client.is_authenticated():
            return client

    username = typer.prompt("Please enter your Vault username")
    password = getpass("Please enter your Vault password (will be hidden): ")
    client.auth.userpass.login(username=username, password=password)
    assert client.is_authenticated(), f"Failed to authenticate to Vault at {vault_addr}"

    # cache the token
    print(f"Caching token to {VAULT_TOKEN_PATH}")
    VAULT_TOKEN_PATH.write_text(client.token)

    return client

@app.command()
def list_secrets(path: str):
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

@app.command()
def put_secret(path, data: Annotated[str, "JSON-encoded data"]):
    secret = json.loads(data)

    client = get_vault_client()
    client.secrets.kv.v2.create_or_update_secret(path=path, secret=secret)

    return f"Saved secret at {path}"

@app.command()
def delete_secret(path):
    client = get_vault_client()
    client.secrets.kv.v2.delete_latest_version_of_secret(path=path)

    return f"Deleted secret at {path}"

if __name__ == "__main__":
    app()
