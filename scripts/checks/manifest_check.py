"""Refuse a manifest.toml that disagrees with gleam.toml, without writing either.

Gleam 1.19 has no frozen mode: whenever manifest.toml's [requirements] table
disagrees with gleam.toml's dependency tables, `gleam check`, `gleam build` and
`gleam deps download` rewrite manifest.toml and exit 0 (Decision 0003, Verify
5). This pre-check runs before any gleam command in the gate and fails on any
difference instead, so drift is reported rather than silently repaired.

Ported from .scratch/bootstrap/evidence/01/manifest/requirements_check.escript
(Decision 0003). The escript compared `taplo get -o json` output; this reads
both files with tomllib and applies the same rule: a bare version string in
gleam.toml means `{ version = ... }`, and gleam reads the dev table under
either spelling, `[dev_dependencies]` or `[dev-dependencies]`.

Usage: python3 scripts/checks/manifest_check.py [project-directory]

SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import sys
import tomllib
from pathlib import Path
from typing import Any

DEV_TABLES = ("dev_dependencies", "dev-dependencies")


def _load(path: Path) -> dict[str, Any]:
    if not path.is_file():
        print(f"manifest-check: {path} is missing; run just initialize", file=sys.stderr)
        raise SystemExit(2)
    with path.open("rb") as stream:
        return tomllib.load(stream)


def _normalise(requirement: object) -> object:
    return {"version": requirement} if isinstance(requirement, str) else requirement


def _wanted(gleam: dict[str, Any]) -> dict[str, object]:
    present = [name for name in DEV_TABLES if name in gleam]
    if len(present) > 1:
        print(
            "manifest-check: gleam.toml has both [dev_dependencies] and [dev-dependencies]; "
            "keep one",
            file=sys.stderr,
        )
        raise SystemExit(2)
    wanted: dict[str, object] = {}
    for name in ("dependencies", *present):
        wanted.update({package: _normalise(spec) for package, spec in gleam.get(name, {}).items()})
    return wanted


def main() -> int:
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else Path()
    wanted = _wanted(_load(directory / "gleam.toml"))
    recorded = _load(directory / "manifest.toml").get("requirements", {})
    if wanted == recorded:
        print("manifest.toml [requirements] matches gleam.toml")
        return 0
    for package in sorted(set(wanted) | set(recorded)):
        if wanted.get(package) != recorded.get(package):
            print(
                f"  {package}: gleam.toml {wanted.get(package, 'absent')}, "
                f"manifest.toml {recorded.get(package, 'absent')}"
            )
    print(
        "manifest.toml disagrees with gleam.toml; run gleam deps download, "
        "read the diff and commit it"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
