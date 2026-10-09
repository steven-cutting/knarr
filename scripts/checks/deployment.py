"""Offline validation with immutable, checksum-verified upstream schemas."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "scripts/schemas/kubernetes"


def verify(source=SCHEMAS):
    provenance = json.loads((source / "sources.json").read_text())
    for name, hashes in provenance["files"].items():
        content = (source / name).read_bytes()
        if hashlib.sha256(content).hexdigest() != hashes["sha256"]:
            raise ValueError(f"upstream schema checksum mismatch: {name}")


def main():
    verify()
    if sys.argv[1:] == ["--render"]:
        content = subprocess.check_output(
            ["kustomize", "build", str(ROOT / "deploy/base")], text=True
        )
    elif not sys.argv[1:]:
        content = (ROOT / "deploy/base/resources.json").read_text()
    else:
        raise ValueError("usage: deployment.py [--render]")
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


if __name__ == "__main__":
    main()
