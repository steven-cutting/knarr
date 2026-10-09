"""Offline validation with immutable, checksum-verified upstream schemas.

With --render, kustomize renders deploy/base and the release overlay over it,
both are validated, and the overlay may change only the container image, to the
published one pinned by digest, and its pull policy (Decision 0012).
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "scripts/schemas/kubernetes"
BASE = ROOT / "deploy/base"
RELEASE = ROOT / "deploy/release"
# What each line the release overlay changes must become.
RELEASE_VALUES = {
    "image": re.compile(r"ghcr\.io/steven-cutting/knarr@sha256:[0-9a-f]{64}"),
    "imagePullPolicy": re.compile(r"IfNotPresent"),
}


def verify(source=SCHEMAS):
    provenance = json.loads((source / "sources.json").read_text())
    for name, hashes in provenance["files"].items():
        content = (source / name).read_bytes()
        if hashlib.sha256(content).hexdigest() != hashes["sha256"]:
            raise ValueError(f"upstream schema checksum mismatch: {name}")


def render(directory):
    return subprocess.check_output(["kustomize", "build", str(directory)], text=True)


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


def overlay_difference(base, release):
    """The release render's image, if it differs from the base render in exactly
    the image and pull-policy lines, as overlay-render.sh in ticket 28 required."""
    base_lines, release_lines = base.splitlines(), release.splitlines()
    if len(release_lines) != len(base_lines):
        raise ValueError(
            f"the release render has {len(release_lines)} lines and the base"
            f" {len(base_lines)}: the overlay adds or removes something"
        )
    changed = {}
    for index, (before, after) in enumerate(zip(base_lines, release_lines, strict=True)):
        if before == after:
            continue
        match = re.fullmatch(r"(\s*(?:- )?)(image|imagePullPolicy): (\S+)", after)
        if (
            not match
            or not before.startswith(f"{match.group(1)}{match.group(2)}: ")
            or match.group(2) in changed
            or not RELEASE_VALUES[match.group(2)].fullmatch(match.group(3))
        ):
            raise ValueError(f"the overlay changes {before.strip()!r} to {after.strip()!r}")
        changed[match.group(2)] = (index, len(match.group(1)), match.group(3))
    missing = [key for key in RELEASE_VALUES if key not in changed]
    if missing:
        raise ValueError(f"the overlay does not change {' or '.join(missing)}")
    # kustomize sorts each container's keys, so its imagePullPolicy is the line
    # after its image, at the same depth.
    image_at, image_depth, image = changed["image"]
    policy_at, policy_depth, _ = changed["imagePullPolicy"]
    if (policy_at, policy_depth) != (image_at + 1, image_depth):
        raise ValueError(
            "the overlay pins the image of one container and the pull policy of another"
        )
    return image


def main():
    verify()
    if sys.argv[1:] == ["--render"]:
        base, release = render(BASE), render(RELEASE)
        validate(base)
        validate(release)
        image = overlay_difference(base, release)
        print(f"release overlay: image {image}, imagePullPolicy IfNotPresent, nothing else")
    elif not sys.argv[1:]:
        validate((BASE / "resources.json").read_text())
    else:
        raise ValueError("usage: deployment.py [--render]")


if __name__ == "__main__":
    main()
