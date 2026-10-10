"""Offline validation with immutable, checksum-verified upstream schemas."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "scripts/schemas/kubernetes"
DEPLOY = ROOT / "deploy"


def variants():
    """Every deployable directory under deploy/: the base and its variants."""
    return sorted(
        path.name for path in DEPLOY.iterdir() if (path / "kustomization.yaml").is_file()
    )


def render(variant):
    if variant not in variants():
        raise ValueError(f"unknown deployment variant: {variant}")
    return subprocess.check_output(["kustomize", "build", str(DEPLOY / variant)], text=True)


def verify(source=SCHEMAS):
    provenance = json.loads((source / "sources.json").read_text())
    for name, hashes in provenance["files"].items():
        content = (source / name).read_bytes()
        if hashlib.sha256(content).hexdigest() != hashes["sha256"]:
            raise ValueError(f"upstream schema checksum mismatch: {name}")


def validate(content):
    subprocess.run(
        [
            "kubeconform",
            "-strict",
            "-summary",
            "-schema-location",
            str(SCHEMAS / "{{.ResourceKind}}{{.KindSuffix}}.json"),
        ],
        input=content,
        text=True,
        check=True,
    )


def main():
    verify()
    arguments = sys.argv[1:]
    if not arguments:
        validate((DEPLOY / "base/resources.json").read_text())
    elif arguments == ["--render"]:
        for variant in variants():
            print(f"rendering deploy/{variant}")
            validate(render(variant))
    elif len(arguments) == 2 and arguments[0] == "--render":
        validate(render(arguments[1]))
    else:
        raise ValueError("usage: deployment.py [--render [variant]]")


if __name__ == "__main__":
    main()
