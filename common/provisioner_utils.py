import json
import os
import subprocess
import sys
from collections import namedtuple
from itertools import chain
from pathlib import Path

import hvac
import typer

SCRIPT_PATH = Path(__file__)
BASE_DIR = SCRIPT_PATH.parent.parent
if str(BASE_DIR) not in sys.path:
    sys.path.append(str(BASE_DIR))

from common.utils import deep_equal
from vault.vault_utils import get_vault_client

ProvisionerEnvironment = namedtuple('ProvisionerEnvironment', [
    'PROV_PROJ_NAME',
    'PROV_BASE_DIR',
    'PROV_CODE_DIR',
    'PROV_RUN_DIR',
])

ProvisionerTools = namedtuple('ProvisionerTools', [
    'env',
    'vault_client',
])

def init_environment(script_path: Path, use_terraform: bool = False):
    proj_name = script_path.parent.name

    env = ProvisionerEnvironment(
        PROV_PROJ_NAME=proj_name,
        PROV_BASE_DIR=BASE_DIR,
        PROV_CODE_DIR=script_path.parent,
        PROV_RUN_DIR=Path('/run') / proj_name,
    )

    # Create directories
    env.PROV_RUN_DIR.mkdir(parents=True, exist_ok=True)

    # Set environment variables
    for key, value in env._asdict().items():
        os.environ[key] = str(value)
    
    vault_client = None

    if use_terraform:
        vault_client = vault_client or get_vault_client()

        # This token is created as a user token in the Terraform Cloud UI:
        # https://app.terraform.io/app/settings/tokens
        os.environ["TF_TOKEN_app_terraform_io"] = vault_client.secrets.kv.v2.read_secret('tfcloud')['data']['data']['access_token']
        os.environ["TF_DATA_DIR"] = str(env.PROV_RUN_DIR / '.terraform')
        
    return ProvisionerTools(env=env, vault_client=vault_client)

def write_terraform_vars(env: ProvisionerEnvironment, vars_dict: dict):
    with open(env.PROV_RUN_DIR / 'terraform.tfvars.json', 'w') as f:
        f.write(json.dumps(vars_dict, indent=2))

def get_terraform_var_flags(env: ProvisionerEnvironment):
    var_flags = []
    for var_file in chain(env.PROV_RUN_DIR.glob('*.tfvars'), env.PROV_RUN_DIR.glob('*.tfvars.json')):
        var_flags.append(f'-var-file={str(var_file)}')

    return var_flags

def run_terraform_generic(env: ProvisionerEnvironment, command: str, additional_args=[], subprocess_args={}):
    return subprocess.run(
        ["terraform", f"-chdir={env.PROV_CODE_DIR}", command] + additional_args,
        check=True,
        **subprocess_args,
    )

def run_terraform_generic_with_var_files(env: ProvisionerEnvironment, command: str, additional_args=[]):
    var_flags = get_terraform_var_flags(env)

    return run_terraform_generic(env, command, var_flags + additional_args)

def run_terraform_init(env: ProvisionerEnvironment, additional_args=[]):
    return run_terraform_generic(env, "init", additional_args)

def run_terraform_plan(env: ProvisionerEnvironment, additional_args=[]):
    return run_terraform_generic_with_var_files(env, "plan", additional_args)

def run_terraform_apply(env: ProvisionerEnvironment, additional_args=[]):
    return run_terraform_generic_with_var_files(env, "apply", additional_args)

def get_terraform_output(env: ProvisionerEnvironment, additional_args=[]):
    res = run_terraform_generic(env, "output", ["-json"] + additional_args, subprocess_args={'capture_output': True, 'text': True})
    
    output = json.loads(res.stdout)

    return output

def run_terraform(tools: ProvisionerTools, vars_dict: dict, additional_init_args=[], additional_plan_args=[], additional_apply_args=[]):
    write_terraform_vars(tools.env, vars_dict)

    run_terraform_init(tools.env, additional_init_args)

    if os.environ.get('DRY_RUN'):
        run_terraform_plan(tools.env, additional_plan_args)
    else:
        run_terraform_apply(tools.env, additional_apply_args)
        output = get_terraform_output(tools.env)
        update_output(tools, output, confirm=os.environ.get('NO_CONFIRM') != "true")

Diff = namedtuple('Diff', ['added', 'removed', 'modified'])

def get_output_diff(old_output: dict, new_output: dict):
    added = {}
    removed = {}
    modified = {}

    for key, value in new_output.items():
        if key not in old_output:
            added[key] = value
        elif not deep_equal(old_output[key], value):
            modified[key] = (old_output[key], value)
        
    for key in old_output.keys():
        if key not in new_output:
            removed[key] = old_output[key]
    
    return Diff(added=added, removed=removed, modified=modified)

def print_diff(diff: Diff):
    print("Output diff:")

    if diff.added:
        print("  Added:")
        for key, value in diff.added.items():
            if isinstance(value, dict) and value.get('sensitive'):
                print(f"    {key}: <sensitive>")
            else:
                print(f"    {key}: {value}")
    else:
        print("  Added: None")
    
    if diff.removed:
        print("  Removed:")
        for key, value in diff.removed.items():
            if isinstance(value, dict) and value.get('sensitive'):
                print(f"    {key}: <sensitive>")
            else:
                print(f"    {key}: {value}")
    else:
        print("  Removed: None")
    
    if diff.modified:
        print("  Modified:")
        for key, (old_value, new_value) in diff.modified.items():
            if isinstance(old_value, dict) and old_value.get('sensitive'):
                old_value = "<sensitive>"
            if isinstance(new_value, dict) and new_value.get('sensitive'):
                new_value = "<sensitive>"

            print(f"    {key}: {old_value} -> {new_value}")
    else:
        print("  Modified: None")

def update_output(tools: ProvisionerTools, output: dict, confirm: bool = True):
    try:
        existing_output = tools.vault_client.secrets.kv.v2.read_secret(f'outputs/{tools.env.PROV_PROJ_NAME}')['data']['data']
    except hvac.exceptions.InvalidPath:
        existing_output = {}

    diff = get_output_diff(existing_output, output)

    if not diff.added and not diff.removed and not diff.modified:
        print("No changes to output")
        return

    print_diff(diff)
    
    if confirm:
        typer.confirm("Do you want to update the output?", abort=True)

    print("Applying output changes...")

    tools.vault_client.secrets.kv.v2.create_or_update_secret(
        path=f"outputs/{tools.env.PROV_PROJ_NAME}",
        secret=dict(output),
    )
