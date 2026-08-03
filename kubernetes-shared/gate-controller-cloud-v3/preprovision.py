import os

DEFAULT_HOST = "gate-controller-cloud-v3.benzhang.dev"


def require_env(name: str):
    value = os.environ.get(name)
    if value:
        return value

    raise RuntimeError(f"Missing required environment variable: {name}")


def get_vars(tools, project):
    return {
        "host": os.environ.get("GATE_CONTROLLER_CLOUD_V3_HOST", DEFAULT_HOST),
        "image": require_env("GATE_CONTROLLER_CLOUD_V3_IMAGE"),
    }
