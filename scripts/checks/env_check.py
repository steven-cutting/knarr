"""Refuse installed tools that pixi.lock or tools.txt no longer pins, without writing.

lock-check proves that pixi.lock agrees with pixi.toml, but nothing in it reads
what is installed. After a pull that moves a pin, every recipe would still run
the old binaries through PATH, and the gate could pass without the pinned
compiler, OTP or lint rules. This compares, without running pixi:

- the packages pixi.lock pins for the default environment, on the platform pixi
    installed it for, with the package records in that environment's conda-meta/;
- each of that platform's tools.txt lines with the pin install-tools.sh recorded
    beside the binary in .tools/bin/.pins/.

No YAML parser is pinned, so pixi.lock is read line by line. The reader knows
lock version 7 and `- conda:` entries only, and refuses anything else rather
than guess.

Usage: python3 scripts/checks/env_check.py [project-directory]

SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import NoReturn

ENVIRONMENT = "default"
LOCK_VERSION = 7
ARCHIVES = (".conda", ".tar.bz2")


def _refuse(message: str) -> NoReturn:
    print(f"env-check: {message}", file=sys.stderr)
    raise SystemExit(2)


def _platform(prefix: Path) -> str:
    """The platform pixi installed the environment for, from its own record."""
    record = prefix / "conda-meta" / "pixi"
    if not record.is_file():
        _refuse(f"{record} is missing; run just initialize")
    try:
        subdir = json.loads(record.read_text(encoding="utf-8"))["resolved_platform"]["subdir"]
    except ValueError, KeyError, TypeError:
        subdir = None
    if not isinstance(subdir, str):
        _refuse(f"{record} names no resolved platform; run just initialize")
    return subdir


def _record_name(url: str) -> str:
    basename = url.rsplit("/", 1)[-1]
    for suffix in ARCHIVES:
        if basename.endswith(suffix):
            return basename.removesuffix(suffix)
    return _refuse(f"pixi.lock entry {url} is not a {' or '.join(ARCHIVES)} archive")


def locked(lock: Path, platform: str) -> set[str]:
    """`name-version-build` of every package pixi.lock pins for ENVIRONMENT on `platform`."""
    if not lock.is_file():
        _refuse(f"{lock} is missing")
    lines = lock.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != f"version: {LOCK_VERSION}":
        _refuse(f"{lock} is not lock version {LOCK_VERSION}, the only one this reader knows")
    target = ["environments:", f"{ENVIRONMENT}:", "packages:", f"{platform}:"]
    keys: dict[int, str] = {}
    found: set[str] = set()
    for number, line in enumerate(lines[1:], start=2):
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        # pixi writes list items at their key's own indent, so the entries of
        # the target platform sit at indent 6 and nothing in it sits deeper.
        inside = [keys.get(level) for level in (0, 2, 4, 6)] == target
        if inside and (indent > 6 or (indent == 6 and text.startswith("- "))):
            entry = re.fullmatch(r"- conda: (\S+)", text)
            if indent > 6 or entry is None:
                _refuse(f"{lock}:{number}: an entry this reader cannot check: {text}")
            found.add(_record_name(entry[1]))
            continue
        if text.startswith("- "):
            continue
        keys = {level: key for level, key in keys.items() if level < indent}
        keys[indent] = text
    if not found:
        _refuse(f"{lock} pins no packages for the {ENVIRONMENT} environment on {platform}")
    return found


def _package_drift(project: Path, prefix: Path, platform: str) -> list[str]:
    pinned = locked(project / "pixi.lock", platform)
    installed = {path.stem for path in (prefix / "conda-meta").glob("*.json")}
    return [
        *(f"  {name}: pinned by pixi.lock, not installed" for name in sorted(pinned - installed)),
        *(f"  {name}: installed, not pinned by pixi.lock" for name in sorted(installed - pinned)),
    ]


def _tool_drift(project: Path, platform: str) -> list[str]:
    pins = project / "tools.txt"
    if not pins.is_file():
        _refuse(f"{pins} is missing")
    tools = project / ".tools" / "bin"
    drift = []
    for line in pins.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if not fields or fields[0].startswith("#"):
            continue
        if len(fields) != 6:
            _refuse(f"{pins}: malformed line for {fields[0]}")
        name, version, pinned_for = fields[:3]
        if pinned_for != platform:
            continue
        stamp = tools / ".pins" / name
        recorded = stamp.read_text(encoding="utf-8").split() if stamp.is_file() else []
        if not os.access(tools / name, os.X_OK) or recorded != fields:
            have = recorded[1] if len(recorded) > 1 else "nothing"
            drift.append(f"  {name}: tools.txt pins {version}, .tools/bin holds {have}")
    return drift


def main() -> int:
    project = Path(sys.argv[1]) if len(sys.argv) > 1 else Path()
    prefix = project / ".pixi" / "envs" / ENVIRONMENT
    platform = _platform(prefix)
    drift = [*_package_drift(project, prefix, platform), *_tool_drift(project, platform)]
    if not drift:
        print(f"the {ENVIRONMENT} environment and .tools/bin match the pins ({platform})")
        return 0
    print("\n".join(drift))
    print(
        "the installed tools differ from pixi.lock or tools.txt; run just initialize "
        "(it needs network for anything not already cached)"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
