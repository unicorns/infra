import importlib
import json
import os
import subprocess
from collections import namedtuple
from itertools import chain
from pathlib import Path

import hvac
import typer

from common.cli_utils import get_app
from common.utils import deep_equal, extract_json_objects
from common.variables import TERRAFORM_CLOUD_SECRETS_PATH
from vault.vault_utils import get_vault_client

SCRIPT_PATH = Path(__file__)
BASE_DIR = SCRIPT_PATH.parent.parent

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

def init_environment(script_path: Path, use_terraform: bool = False, use_terragrunt: bool = False):
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

    if use_terraform or use_terragrunt:
        vault_client = vault_client or get_vault_client()

        os.environ["TF_TOKEN_app_terraform_io"] = vault_client.secrets.kv.v2.read_secret(
            TERRAFORM_CLOUD_SECRETS_PATH
        )['data']['data']['access_token']

    if use_terraform:
        os.environ["TF_DATA_DIR"] = str(env.PROV_RUN_DIR / '.terraform')
    
    if use_terragrunt:
        # Terragrunt downloads and runs the Terraform project in this directory
        # https://terragrunt.gruntwork.io/docs/reference/cli-options/#terragrunt-download-dir
        os.environ["TERRAGRUNT_DOWNLOAD"] = str(env.PROV_RUN_DIR / '.terragrunt-cache')
        
    return ProvisionerTools(env=env, vault_client=vault_client)

############################################
# Terraform functions
############################################

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
    return run_terraform_generic(env, "init", [ "-lock-timeout=20m" ] + additional_args)

def run_terraform_plan(env: ProvisionerEnvironment, additional_args=[]):
    return run_terraform_generic_with_var_files(env, "plan", [ "-lock-timeout=20m", "-refresh=false" ] + additional_args)

def run_terraform_apply(env: ProvisionerEnvironment, additional_args=[]):
    return run_terraform_generic_with_var_files(env, "apply", [ "-lock-timeout=20m" ] + additional_args)

def get_terraform_output(env: ProvisionerEnvironment, additional_args=[]):
    res = run_terraform_generic(env, "output", ["-json"] + additional_args, subprocess_args={'capture_output': True, 'text': True})
    assert res.returncode == 0, f"Failed to get Terraform output: {res.stderr}"
    output = next(extract_json_objects(res.stdout))

    return output

def get_terraform_state(env: ProvisionerEnvironment, additional_args=[]):
    res = run_terraform_generic(env, "state", ["pull"] + additional_args, subprocess_args={'capture_output': True, 'text': True})
    assert res.returncode == 0, f"Failed to get Terraform state: {res.stderr}"
    state = next(extract_json_objects(res.stdout))

    return state

def run_terraform(tools: ProvisionerTools, vars_dict: dict, additional_init_args=[], additional_plan_args=[], additional_apply_args=[]):
    write_terraform_vars(tools.env, vars_dict)

    run_terraform_init(tools.env, additional_init_args)

    if os.environ.get('DRY_RUN'):
        run_terraform_plan(tools.env, additional_plan_args)
    else:
        run_terraform_apply(tools.env, additional_apply_args + (["-auto-approve"] if os.environ.get('NO_CONFIRM') else []))
        print("Checking whether to update output...")
        output = get_terraform_output(tools.env)
        update_output(tools, output, confirm=os.environ.get('NO_CONFIRM') != "true")
        if os.environ.get('BACK_UP_STATE'):
            state = get_terraform_state(tools.env)
            back_up_state(tools, state, confirm=os.environ.get('NO_CONFIRM') != "true")

############################################
# Terragrunt functions
############################################

def run_terragrunt_generic(args = [],  subprocess_args={}):
    return subprocess.run(
        ["terragrunt"] + args,
        check=True,
        **subprocess_args,
    )

def run_terragrunt_generic_with_project(env: ProvisionerEnvironment, project: str, command: str, additional_args=[], subprocess_args={}):
    if not subprocess_args.get('env'):
        subprocess_args["env"] = os.environ.copy()
    
    if project == "__all__":
        subprocess_args["env"]["TERRAGRUNT_WORKING_DIR"] = str(env.PROV_CODE_DIR)
        return run_terragrunt_generic(["run-all", command, "--terragrunt-exclude-dir=_*"] + additional_args, subprocess_args=subprocess_args)
    else:
        subprocess_args["env"]["TERRAGRUNT_WORKING_DIR"] = str(env.PROV_CODE_DIR / project)
        return run_terragrunt_generic([command] + additional_args, subprocess_args=subprocess_args)

def write_terragrunt_vars(env: ProvisionerEnvironment, project: str, vars_dict: dict):
    vars_file = env.PROV_RUN_DIR / project / 'terraform.tfvars.json'
    vars_file.parent.mkdir(parents=True, exist_ok=True)
    with open(vars_file, 'w') as f:
        f.write(json.dumps(vars_dict, indent=2))

def run_terragrunt(
    tools: ProvisionerTools,
    project: str,
    additional_init_args=[],
    additional_plan_args=[],
    additional_apply_args=[],
):
    """
    Run Terragrunt with the given project name. When `project` is `__all__`, run Terragrunt on all projects.
    """
    run_terragrunt_generic_with_project(tools.env, project, "init", additional_init_args)

    if os.environ.get("DRY_RUN"):
        run_terragrunt_generic_with_project(tools.env, project, "plan", additional_plan_args)
    else:
        run_terragrunt_generic_with_project(tools.env, project, "apply", additional_apply_args + (["--terragrunt-non-interactive"] if os.environ.get("NO_CONFIRM") else []))

def import_preprovision_module(project: str, package: str):
    try:
        # Support both executing the top-level script directly (python path/to/script.py)
        # and running it as a package (python -m path.to.script)
        # - https://stackoverflow.com/a/49480246
        # - https://stackoverflow.com/a/14132912
        if package:
            mod = importlib.import_module(f".{project}.preprovision", package)
        else:
            mod = importlib.import_module(f"{project}.preprovision")
        return mod
    except ModuleNotFoundError:
        return None

def make_terragrunt_command(script_path, project, package, get_global_vars_fn):
    """
    Create a Terragrunt command function for a specific project.
    """

    def command():
        tools = init_environment(script_path, use_terragrunt=True)
        write_terragrunt_vars(tools.env, "", get_global_vars_fn(tools))

        mod = import_preprovision_module(project, package)
        if mod:
            write_terragrunt_vars(tools.env, project, mod.get_vars(tools, project))

        run_terragrunt(tools=tools, project=project)

        # Get output
        print("Checking whether to update output...")
        res = run_terragrunt_generic_with_project(tools.env, project, "output", ["-json"], subprocess_args={'capture_output': True, 'text': True})
        assert res.returncode == 0, f"Failed to get Terragrunt output for project '{project}': {res.stderr}"
        output = next(extract_json_objects(res.stdout))
        update_output(tools, output, subpath=f"{tools.env.PROV_PROJ_NAME}/{project}", confirm=os.environ.get("NO_CONFIRM") != "true")
        
        if os.environ.get("BACK_UP_STATE"):
            res = run_terragrunt_generic_with_project(tools.env, project, "state", ["pull"], subprocess_args={'capture_output': True, 'text': True})
            assert res.returncode == 0, f"Failed to get Terragrunt state for project '{project}': {res.stderr}"
            state = next(extract_json_objects(res.stdout))
            back_up_state(tools, state, subpath=f"{tools.env.PROV_PROJ_NAME}/{project}", confirm=os.environ.get("NO_CONFIRM") != "true")

    return command

def make_terragrunt_app(script_path: Path, package: str, get_global_vars_fn: callable):
    """
    Create a Typer app for provisioning a Terragrunt project.
    """

    app = get_app()

    projects = [
        f.parent.name
        for f in script_path.parent.glob("*/terragrunt.hcl")
        if not f.parent.name.startswith("_")
    ]

    for project in projects:
        # Register projects with Typer
        app.command(name=project)(make_terragrunt_command(script_path, project, package, get_global_vars_fn))

    @app.command()
    def all():
        tools = init_environment(script_path, use_terragrunt=True)
        write_terragrunt_vars(tools.env, "", get_global_vars_fn(tools))

        # write vars for each project
        for project in projects:
            mod = import_preprovision_module(project, package)
            if mod:
                write_terragrunt_vars(tools.env, project, mod.get_vars(tools, project))

        run_terragrunt(tools=tools, project="__all__")

        outputs = {}
        diffs = {}

        # Get output
        for project in projects:
            print(f"Getting output for project '{project}'...")
            res = run_terragrunt_generic_with_project(tools.env, project, "output", ["-json"], subprocess_args={'capture_output': True, 'text': True})
            assert res.returncode == 0, f"Failed to get Terragrunt output for project '{project}': {res.stderr}"
            output = next(extract_json_objects(res.stdout))
            outputs[project] = output
            diff = update_output(tools, output, subpath=f"{tools.env.PROV_PROJ_NAME}/{project}", dry_run=True)
            if diff:
                diffs[project] = diff
            
        
        if len(diffs) > 0:
            if os.environ.get("NO_CONFIRM") or typer.confirm("Do you want to apply the changes?"):
                for project, diff in diffs.items():
                    print(f"Applying output changes for project '{project}'...")
                    update_output(tools, outputs[project], subpath=f"{tools.env.PROV_PROJ_NAME}/{project}", confirm=False)
            else:
                print("Not applying output changes")

        if os.environ.get("BACK_UP_STATE"):
            states = {}
            state_has_diffs = {}

            for project in projects:
                print(f"Getting state for project '{project}'...")

                res = run_terragrunt_generic_with_project(tools.env, project, "state", ["pull"], subprocess_args={'capture_output': True, 'text': True})
                assert res.returncode == 0, f"Failed to get Terragrunt state for project '{project}': {res.stderr}"
                state = next(extract_json_objects(res.stdout))
                states[project] = state
                has_diff = back_up_state(tools, state, subpath=f"{tools.env.PROV_PROJ_NAME}/{project}", dry_run=True)
                state_has_diffs[project] = has_diff
            
            if any(state_has_diffs.values()):
                if os.environ.get("NO_CONFIRM") or typer.confirm("Do you want to back up the states?"):
                    for project, has_diff in state_has_diffs.items():
                        if has_diff:
                            print(f"Backing up state for project '{project}'...")
                            back_up_state(tools, states[project], subpath=f"{tools.env.PROV_PROJ_NAME}/{project}", confirm=False)
                else:
                    print("Not backing up states")


    return app

############################################
# Output functions
############################################

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

def update_output(tools: ProvisionerTools, output: dict, subpath: str = None, confirm: bool = True, dry_run: bool = False):
    if not subpath:
        subpath = tools.env.PROV_PROJ_NAME

    try:
        existing_output = tools.vault_client.secrets.kv.v2.read_secret(f'outputs/{subpath}')['data']['data']
    except hvac.exceptions.InvalidPath:
        existing_output = {}

    diff = get_output_diff(existing_output, output)

    if not diff.added and not diff.removed and not diff.modified:
        print("No changes to output")
        return None

    print_diff(diff)

    if dry_run:
        return diff

    if confirm and not typer.confirm("Do you want to update the output (may require elevated permissions)?"):
        return diff

    print("Applying output changes...")

    tools.vault_client.secrets.kv.v2.create_or_update_secret(
        path=f"outputs/{subpath}",
        secret=dict(output),
    )

    return diff

def back_up_state(tools: ProvisionerTools, state: dict, subpath: str = None, confirm: bool = True, dry_run: bool = False):
    if not subpath:
        subpath = tools.env.PROV_PROJ_NAME

    try:
        existing_state = tools.vault_client.secrets.kv.v2.read_secret(f'states/{subpath}')['data']['data']
    except hvac.exceptions.InvalidPath:
        existing_state = {}

    if deep_equal(existing_state, state):
        print("No state changes")
        return False

    print("Detected state changes")

    if dry_run:
        return True

    if confirm and not typer.confirm("Do you want to back up the state?"):
        return True
    
    print("Backing up state changes...")

    tools.vault_client.secrets.kv.v2.create_or_update_secret(
        path=f"states/{subpath}",
        secret=dict(state),
    )
