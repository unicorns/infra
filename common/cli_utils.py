import json
import sys
from enum import Enum

import typer
import yaml


class TyperOutputFormat(str, Enum):
    yaml = "yaml"
    json = "json"
    raw = "raw"


# Encode set as list during JSON serialization
# Derived from https://stackoverflow.com/a/8230505
class JSONSetEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, set):
            return list(obj)
        return json.JSONEncoder.default(self, obj)


def default_print_retval(ret: dict | list, output_format: TyperOutputFormat, **kwargs):
    if output_format == TyperOutputFormat.yaml:
        print(yaml.dump(ret, default_flow_style=False))
    elif output_format == TyperOutputFormat.json:
        print(json.dumps(ret, indent=2, cls=JSONSetEncoder))
    elif output_format == TyperOutputFormat.raw:
        sys.stdout.write(ret)


def get_app(default_output_format: TyperOutputFormat = TyperOutputFormat.yaml, callback_fn=None, print_retval_fn=None):
    if print_retval_fn is None:
        print_retval_fn = default_print_retval

    app = typer.Typer(result_callback=print_retval_fn)

    if callback_fn is None:
        @app.callback()
        def default_callback(output_format: TyperOutputFormat = default_output_format):
            pass
    else:
        app.callback()(callback_fn)

    return app
