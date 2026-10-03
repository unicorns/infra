import base64
import json
import os
import subprocess
from pathlib import Path


ENV_VARS = {
    "acme_email": "PRIVATE_INGRESS_ACME_EMAIL",
    "cloudflare_zone_id": "CLOUDFLARE_ZONE_ID",
    "tailscale_client_id": "TAILSCALE_CLIENT_ID",
    "tailscale_audience": "TAILSCALE_AUDIENCE",
}


def get_vars(tools, project):
    required = [*ENV_VARS.values(), "CLOUDFLARE_API_TOKEN"]
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError(
            "Missing private ingress configuration: " + ", ".join(missing)
        )

    global_vars = json.loads(
        (tools.env.PROV_RUN_DIR / "terraform.tfvars.json").read_text()
    )
    kubectl = ["kubectl", "--kubeconfig", global_vars["kube_config_path"]]

    if os.environ.get("DRY_RUN"):
        subprocess.run(
            [*kubectl, "get", "--raw", "/readyz"],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        subprocess.run(
            [*kubectl, "auth", "can-i", "create", "namespaces", "--quiet"],
            check=True,
        )
        subprocess.run(
            [
                *kubectl,
                "auth",
                "can-i",
                "patch",
                "secrets",
                "--namespace",
                "private-ingress",
                "--quiet",
            ],
            check=True,
        )
    else:
        subprocess.run(
            [
                *kubectl,
                "apply",
                "--server-side",
                "--field-manager",
                "unicorns-infra",
                "-f",
                str(Path(__file__).with_name("namespace.yaml")),
            ],
            check=True,
        )
        token = os.environ["CLOUDFLARE_API_TOKEN"]
        encoded_token = base64.b64encode(token.encode()).decode()
        secret = {
            "apiVersion": "v1",
            "kind": "Secret",
            "metadata": {
                "name": "cloudflare-api-token",
                "namespace": "private-ingress",
            },
            "type": "Opaque",
            "data": {"api-token": encoded_token},
        }
        result = subprocess.run(
            [
                *kubectl,
                "apply",
                "--server-side",
                "--field-manager",
                "unicorns-infra",
                "-f",
                "-",
            ],
            input=json.dumps(secret),
            capture_output=True,
            text=True,
        )
        if result.returncode:
            detail = result.stderr.replace(token, "[redacted]").replace(
                encoded_token, "[redacted]"
            )
            raise RuntimeError(f"Failed to apply Cloudflare API token Secret: {detail}")

    return {name: os.environ[env_name] for name, env_name in ENV_VARS.items()}
