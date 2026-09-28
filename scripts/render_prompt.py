#!/usr/bin/env python3
"""Render a Jinja2 prompt template to stdout.

usage: render_prompt.py <template.j2> [json_vars]

Variables come from a JSON object passed as the second argument (default: {}).
Rendering is strict: a variable used without a default and not provided is an
error. Whitespace is normalized to single spaces (prompts are single-line).
"""
import json
import sys

try:
    from jinja2 import Environment, StrictUndefined, TemplateError
except ImportError:
    sys.exit("ERROR: jinja2 is required (scripts/setup.sh installs it). Run: uv pip install jinja2")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    template_path = sys.argv[1]
    variables = {}
    if len(sys.argv) > 2 and sys.argv[2].strip():
        variables = json.loads(sys.argv[2])
        if not isinstance(variables, dict):
            sys.exit("ERROR: vars must be a JSON object")

    env = Environment(undefined=StrictUndefined, keep_trailing_newline=False, autoescape=False)
    with open(template_path) as f:
        template = env.from_string(f.read())
    try:
        rendered = template.render(**variables)
    except TemplateError as e:
        sys.exit(f"ERROR: failed to render {template_path}: {e}")
    print(" ".join(rendered.split()))


if __name__ == "__main__":
    main()
