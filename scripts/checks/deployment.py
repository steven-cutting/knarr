"""Offline validation with immutable, checksum-verified upstream schemas."""

from __future__ import annotations

import gzip
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "scripts/schemas/kubernetes"


def unpack(destination, source=SCHEMAS):
    provenance = json.loads((source / "sources.json").read_text())
    for name, hashes in provenance["files"].items():
        compressed = (source / f"{name}.gz").read_bytes()
        if hashlib.sha256(compressed).hexdigest() != hashes["gzip_sha256"]:
            raise ValueError(f"compressed schema checksum mismatch: {name}")
        content = gzip.decompress(compressed)
        if hashlib.sha256(content).hexdigest() != hashes["sha256"]:
            raise ValueError(f"upstream schema checksum mismatch: {name}")
        (destination / name).write_bytes(content)


def main():
    with tempfile.TemporaryDirectory(prefix="knarr-schemas-") as temporary:
        destination = Path(temporary)
        unpack(destination)
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
                str(destination / "{{.ResourceKind}}{{.KindSuffix}}.json"),
            ],
            input=content,
            text=True,
            check=True,
        )


if __name__ == "__main__":
    main()
