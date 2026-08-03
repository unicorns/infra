import importlib.util
import json
import os
import subprocess
from collections import namedtuple
from itertools import chain
from pathlib import Path

from common.cli_utils import get_app


BASE_DIR = Path(__file__).parent.parent

ProvisionerEnvironment = namedtuple(
    "ProvisionerEnvironment",
    ["PROV_PROJ_NAME", "PROV_BASE_DIR", "PROV_CODE_DIR", "PROV_RUN_DIR"],
)
ProvisionerTools = namedtuple("ProvisionerTools", ["env"])


def init_environment(
    script_path: Path,
    use_terraform: bool = False,
    use_terragrunt: bool = False,
):
    project_name = script_path.parent.name
    env = ProvisionerEnvironment(
        PROV_PROJ_NAME=project_name,
        PROV_BASE_DIR=BASE_DIR,
        PROV_CODE_DIR=script_path.parent,
        PROV_RUN_DIR=Path("/run") / project_name,
    )

    env.PROV_RUN_DIR.mkdir(parents=True, exist_ok=True)
    for key, value in env._asdict().items():
        os.environ[key] = str(value)

    if (use_terraform or use_terragrunt) and not os.environ.get(
        "TF_TOKEN_app_terraform_io"
    ):
        raise RuntimeError("Missing TF_TOKEN_app_terraform_io.")

    if use_terraform:
        os.environ["TF_DATA_DIR"] = str(env.PROV_RUN_DIR / ".terraform")

    if use_terragrunt:
        os.environ["TERRAGRUNT_DOWNLOAD"] = str(
            env.PROV_RUN_DIR / ".terragrunt-cache"
        )

    return ProvisionerTools(env=env)


def write_terraform_vars(env: ProvisionerEnvironment, variables: dict):
    with open(env.PROV_RUN_DIR / "terraform.tfvars.json", "w") as file:
        json.dump(variables, file, indent=2)


def get_terraform_var_flags(env: ProvisionerEnvironment):
    var_files = chain(
        env.PROV_RUN_DIR.glob("*.tfvars"),
        env.PROV_RUN_DIR.glob("*.tfvars.json"),
    )
    return [f"-var-file={var_file}" for var_file in var_files]


def run_terraform_generic(
    env: ProvisionerEnvironment,
    command: str,
    additional_args=None,
    subprocess_args=None,
):
    return subprocess.run(
        ["terraform", f"-chdir={env.PROV_CODE_DIR}", command]
        + (additional_args or []),
        check=True,
        **(subprocess_args or {}),
    )


def run_terraform_generic_with_var_files(
    env: ProvisionerEnvironment,
    command: str,
    additional_args=None,
):
    return run_terraform_generic(
        env,
        command,
        get_terraform_var_flags(env) + (additional_args or []),
    )


def run_terraform_init(env: ProvisionerEnvironment, additional_args=None):
    return run_terraform_generic(
        env,
        "init",
        ["-lock-timeout=20m"] + (additional_args or []),
    )


def run_terraform_plan(env: ProvisionerEnvironment, additional_args=None):
    return run_terraform_generic_with_var_files(
        env,
        "plan",
        ["-lock-timeout=20m", "-refresh=false"] + (additional_args or []),
    )


def run_terraform_apply(env: ProvisionerEnvironment, additional_args=None):
    return run_terraform_generic_with_var_files(
        env,
        "apply",
        ["-lock-timeout=20m"] + (additional_args or []),
    )


def get_terraform_output(env: ProvisionerEnvironment):
    result = run_terraform_generic(
        env,
        "output",
        ["-json"],
        subprocess_args={"capture_output": True, "text": True},
    )
    return json.loads(result.stdout)


def run_terraform(
    tools: ProvisionerTools,
    variables: dict,
    additional_init_args=None,
    additional_plan_args=None,
    additional_apply_args=None,
):
    write_terraform_vars(tools.env, variables)
    run_terraform_init(tools.env, additional_init_args)

    if os.environ.get("DRY_RUN"):
        run_terraform_plan(tools.env, additional_plan_args)
        return

    approval_args = ["-auto-approve"] if os.environ.get("NO_CONFIRM") else []
    run_terraform_apply(
        tools.env,
        (additional_apply_args or []) + approval_args,
    )


def run_terragrunt_generic(args=None, subprocess_args=None):
    return subprocess.run(
        ["terragrunt"] + (args or []),
        check=True,
        **(subprocess_args or {}),
    )


def run_terragrunt_generic_with_project(
    env: ProvisionerEnvironment,
    project: str,
    command: str,
    additional_args=None,
    subprocess_args=None,
):
    command_env = os.environ.copy()
    if subprocess_args and subprocess_args.get("env"):
        command_env = subprocess_args["env"]

    args = additional_args or []
    if project == "__all__":
        command_env["TERRAGRUNT_WORKING_DIR"] = str(env.PROV_CODE_DIR)
        command_args = [
            "run-all",
            command,
            "--terragrunt-exclude-dir=_*",
            *args,
        ]
    else:
        command_env["TERRAGRUNT_WORKING_DIR"] = str(env.PROV_CODE_DIR / project)
        command_args = [command, *args]

    options = dict(subprocess_args or {})
    options["env"] = command_env
    return run_terragrunt_generic(command_args, options)


def write_terragrunt_vars(
    env: ProvisionerEnvironment,
    project: str,
    variables: dict,
):
    variables_file = env.PROV_RUN_DIR / project / "terraform.tfvars.json"
    variables_file.parent.mkdir(parents=True, exist_ok=True)
    with open(variables_file, "w") as file:
        json.dump(variables, file, indent=2)


def run_terragrunt(
    tools: ProvisionerTools,
    project: str,
    additional_init_args=None,
    additional_plan_args=None,
    additional_apply_args=None,
):
    run_terragrunt_generic_with_project(
        tools.env,
        project,
        "init",
        ["-lockfile=readonly", *(additional_init_args or [])],
    )

    if os.environ.get("DRY_RUN"):
        run_terragrunt_generic_with_project(
            tools.env,
            project,
            "plan",
            additional_plan_args,
        )
        return

    approval_args = (
        ["--terragrunt-non-interactive", "-auto-approve"]
        if os.environ.get("NO_CONFIRM")
        else []
    )
    run_terragrunt_generic_with_project(
        tools.env,
        project,
        "apply",
        (additional_apply_args or []) + approval_args,
    )


def import_preprovision_module(script_path: Path, project: str):
    module_path = script_path.parent / project / "preprovision.py"
    if not module_path.is_file():
        return None

    module_name = f"{script_path.parent.name}_{project}_preprovision".replace(
        "-",
        "_",
    )
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if not spec or not spec.loader:
        raise RuntimeError(f"Unable to load preprovision module: {module_path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_terragrunt_command(
    script_path: Path,
    project: str,
    get_global_vars,
):
    def command():
        tools = init_environment(script_path, use_terragrunt=True)
        write_terragrunt_vars(tools.env, "", get_global_vars(tools))

        preprovision = import_preprovision_module(script_path, project)
        if preprovision:
            write_terragrunt_vars(
                tools.env,
                project,
                preprovision.get_vars(tools, project),
            )

        run_terragrunt(tools, project)

    return command


def make_terragrunt_app(
    script_path: Path,
    get_global_vars,
):
    app = get_app()
    projects = [
        file.parent.name
        for file in script_path.parent.glob("*/terragrunt.hcl")
        if not file.parent.name.startswith("_")
    ]

    for project in projects:
        app.command(name=project)(
            make_terragrunt_command(
                script_path,
                project,
                get_global_vars,
            )
        )

    @app.command()
    def all():
        tools = init_environment(script_path, use_terragrunt=True)
        write_terragrunt_vars(tools.env, "", get_global_vars(tools))

        for project in projects:
            preprovision = import_preprovision_module(script_path, project)
            if preprovision:
                write_terragrunt_vars(
                    tools.env,
                    project,
                    preprovision.get_vars(tools, project),
                )

        run_terragrunt(tools, "__all__")

    return app
