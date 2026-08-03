import os


def get_env_value(*names):
    for name in names:
        if value := os.environ.get(name):
            return value

    return None
