import json
import os
import subprocess
import sys
from collections import namedtuple
from itertools import chain
from pathlib import Path

SCRIPT_PATH = Path(__file__)
BASE_DIR = SCRIPT_PATH.parent.parent
if str(BASE_DIR) not in sys.path:
    sys.path.append(str(BASE_DIR))

from vault.vault_utils import get_vault_client

ProvisionerEnvironment = namedtuple('ProvisionerEnvironment', [
    'PROV_PROJ_NAME',
    'PROV_BASE_DIR',
    'PROV_CODE_DIR',
    'PROV_RUN_DIR',
    'PROV_OUTPUT_DIR',
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
        PROV_OUTPUT_DIR=BASE_DIR / "outputs" / proj_name,
    )

    # Create directories
    env.PROV_RUN_DIR.mkdir(parents=True, exist_ok=True)
    env.PROV_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

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

def run_terraform_generic(env: ProvisionerEnvironment, command: str, additional_args=[]):
    return subprocess.run(
        ["terraform", f"-chdir={env.PROV_CODE_DIR}", command] + additional_args,
        check=True,
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

def run_terraform(env: ProvisionerEnvironment, vars_dict: dict, additional_init_args=[], additional_plan_args=[], additional_apply_args=[]):
    write_terraform_vars(env, vars_dict)

    run_terraform_init(env, additional_init_args)

    if os.environ.get('DRY_RUN'):
        return run_terraform_plan(env, additional_plan_args)
    else:
        return run_terraform_apply(env, additional_apply_args)
