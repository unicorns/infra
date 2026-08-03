#!/usr/bin/env python3

from pathlib import Path
import json
import os
import subprocess
import urllib.parse
import urllib.request

from common.cli_utils import get_app
from common.provisioner_utils import (
    init_environment,
    run_terraform,
    run_terraform_generic_with_var_files,
    run_terraform_init,
    write_terraform_vars,
)
from common.utils import get_env_value

SCRIPT_PATH = Path(__file__)
DEFAULT_ZONE_NAME = "benzhang.dev"
DEFAULT_GATE_CONTROLLER_HOSTNAME = "gate-controller-cloud-v3.benzhang.dev"
GATE_CONTROLLER_RESOURCE_ADDRESS = "cloudflare_record.gate_controller"

app = get_app()


def parse_bool(value: str):
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False

    raise ValueError(f"Invalid boolean value: {value}")


def get_env_tf_vars():
    tf_vars = {}

    if token := get_env_value("CLOUDFLARE_API_TOKEN", "CF_API_TOKEN"):
        tf_vars["cloudflare_api_token"] = token

    if zone_name := get_env_value("CLOUDFLARE_ZONE_NAME"):
        tf_vars["zone_name"] = zone_name

    if origin_ip := get_env_value(
        "GATE_CONTROLLER_ORIGIN_IP",
        "INGRESS_EXTERNAL_IP",
        "AKS_INGRESS_EXTERNAL_IP",
    ):
        tf_vars["gate_controller_origin_ip"] = origin_ip

    if hostname := get_env_value("GATE_CONTROLLER_CLOUD_V3_HOST"):
        tf_vars["gate_controller_hostname"] = hostname

    if proxied := get_env_value("GATE_CONTROLLER_CLOUDFLARE_PROXIED"):
        tf_vars["gate_controller_proxied"] = parse_bool(proxied)

    return tf_vars


def require_tf_var(tf_vars: dict, name: str, default=None):
    value = tf_vars.get(name, default)
    if value:
        return value

    raise RuntimeError(f"Missing required Terraform variable: {name}")


def cloudflare_get(token: str, path: str, params: dict):
    query = urllib.parse.urlencode(params)
    request = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/{path}?{query}",
        headers={"Authorization": f"Bearer {token}"},
    )

    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)

    if not payload.get("success"):
        errors = payload.get("errors", [])
        raise RuntimeError(f"Cloudflare API request failed: {errors}")

    return payload["result"]


def find_zone_id(token: str, zone_name: str):
    zones = cloudflare_get(token, "zones", {"name": zone_name, "per_page": 1})
    if not zones:
        raise RuntimeError(f"Cloudflare zone not found: {zone_name}")

    return zones[0]["id"]


def find_dns_record_id(token: str, zone_id: str, hostname: str, record_type: str):
    records = cloudflare_get(
        token,
        f"zones/{zone_id}/dns_records",
        {
            "name": hostname,
            "type": record_type,
            "per_page": 100,
        },
    )
    if not records:
        return None

    if len(records) > 1:
        raise RuntimeError(
            f"Expected at most one {record_type} record for {hostname}, found {len(records)}."
        )

    return records[0]["id"]


def state_has_resource(tools, address: str):
    result = subprocess.run(
        ["terraform", f"-chdir={tools.env.PROV_CODE_DIR}", "state", "list"],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        if "No state file was found" in result.stderr:
            return False

        result.check_returncode()

    return address in result.stdout.splitlines()


def import_gate_controller_record(tools, tf_vars: dict):
    write_terraform_vars(tools.env, tf_vars)
    run_terraform_init(tools.env)

    if state_has_resource(tools, GATE_CONTROLLER_RESOURCE_ADDRESS):
        print(f"{GATE_CONTROLLER_RESOURCE_ADDRESS} is already in Terraform state.")
        return

    token = require_tf_var(tf_vars, "cloudflare_api_token")
    zone_name = require_tf_var(tf_vars, "zone_name", DEFAULT_ZONE_NAME)
    hostname = require_tf_var(
        tf_vars,
        "gate_controller_hostname",
        DEFAULT_GATE_CONTROLLER_HOSTNAME,
    )
    zone_id = find_zone_id(token, zone_name)
    record_id = find_dns_record_id(token, zone_id, hostname, "A")

    if not record_id:
        print(f"No existing A record found for {hostname}; Terraform will create it.")
        return

    import_id = f"{zone_id}/{record_id}"
    run_terraform_generic_with_var_files(
        tools.env,
        "import",
        [GATE_CONTROLLER_RESOURCE_ADDRESS, import_id],
    )


@app.command(name="import-gate-controller")
def import_gate_controller():
    tools = init_environment(SCRIPT_PATH, use_terraform=True, use_vault=False)
    import_gate_controller_record(tools, get_env_tf_vars())


@app.command()
def all():
    tools = init_environment(SCRIPT_PATH, use_terraform=True, use_vault=False)
    tf_vars = get_env_tf_vars()

    if not os.environ.get("DRY_RUN"):
        import_gate_controller_record(tools, tf_vars)

    run_terraform(tools, tf_vars)


if __name__ == "__main__":
    app()
