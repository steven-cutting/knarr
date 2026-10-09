"""Report the hex packages and the Erlang/OTP release that OSV.dev lists an advisory for.

The audit workflow runs this weekly, outside the offline gate, because the
answer changes without any commit (Decision 0013). It asks api.osv.dev once,
with one querybatch request:

- every hex package manifest.toml locks, by its Hex name and version, in OSV's
    `Hex` ecosystem;
- the `erlang` pin in pixi.toml, as the `OTP-<version>` tag of
    github.com/erlang/otp, in OSV's `GIT` ecosystem, which is where OSV records
    the OTP advisories.

It fails closed: an answer it cannot read in full is "cannot decide", never a
pass.

Usage: python3 scripts/checks/hex_audit.py [project-directory]
Exit status: 0 no advisory, 1 advisories found, 2 cannot decide.

SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import json
import re
import sys
import tomllib
import urllib.request
from pathlib import Path
from typing import TYPE_CHECKING, NamedTuple

if TYPE_CHECKING:
    from collections.abc import Callable

OTP_REPOSITORY = "https://github.com/erlang/otp"
ADVISORY = "https://osv.dev/vulnerability/"


class CannotDecideError(Exception):
    """The audit has no whole answer to judge."""


class Subject(NamedTuple):
    ecosystem: str
    name: str
    version: str

    def __str__(self) -> str:
        if self.ecosystem == "GIT":
            return f"Erlang/OTP {self.version.removeprefix('OTP-')}"
        return f"{self.name} {self.version}"


def hex_packages(manifest_text: str) -> list[tuple[str, str]]:
    """(name, version) of every package manifest.toml locks from Hex."""
    try:
        packages = tomllib.loads(manifest_text)["packages"]
        return sorted(
            (package["name"], package["version"])
            for package in packages
            if package.get("source") == "hex"
        )
    except (tomllib.TOMLDecodeError, KeyError, TypeError) as error:
        raise CannotDecideError(f"manifest.toml has no readable packages list: {error}") from error


def otp_release(pixi_text: str) -> str:
    """The OTP release the exact `erlang` pin in pixi.toml names."""
    try:
        pin = tomllib.loads(pixi_text)["feature"]["otp"]["dependencies"]["erlang"]
    except (tomllib.TOMLDecodeError, KeyError, TypeError) as error:
        raise CannotDecideError(
            f"pixi.toml has no erlang pin in [feature.otp]: {error}"
        ) from error
    match = re.fullmatch(r"==(\d+(?:\.\d+)*)", pin) if isinstance(pin, str) else None
    if match is None:
        raise CannotDecideError(f"the erlang pin {pin!r} is not one exact version")
    return match[1]


def subjects(project: Path) -> list[Subject]:
    """Everything one audit of `project` asks about, the OTP release last."""
    try:
        manifest = (project / "manifest.toml").read_text(encoding="utf-8")
        pixi = (project / "pixi.toml").read_text(encoding="utf-8")
    except OSError as error:
        raise CannotDecideError(str(error)) from error
    return [
        *(Subject("Hex", name, version) for name, version in hex_packages(manifest)),
        Subject("GIT", OTP_REPOSITORY, f"OTP-{otp_release(pixi)}"),
    ]


def batch_query(audited: list[Subject]) -> dict[str, object]:
    """The body of one OSV querybatch request, one query per subject, in order."""
    return {
        "queries": [
            {"package": {"ecosystem": s.ecosystem, "name": s.name}, "version": s.version}
            for s in audited
        ]
    }


def findings(audited: list[Subject], answer: object) -> list[str]:
    """One line per advisory OSV lists, or CannotDecideError for an answer not read in full."""
    results = answer.get("results") if isinstance(answer, dict) else None
    if not isinstance(results, list) or len(results) != len(audited):
        count = len(results) if isinstance(results, list) else "no"
        raise CannotDecideError(f"OSV answered {count} results for {len(audited)} queries")
    lines = []
    for subject, result in zip(audited, results, strict=True):
        if not isinstance(result, dict):
            raise CannotDecideError(f"OSV's result for {subject} is not an object")
        if "next_page_token" in result:
            raise CannotDecideError(f"OSV has a further page of advisories for {subject}")
        advisories = result.get("vulns", [])
        if not isinstance(advisories, list):
            raise CannotDecideError(f"OSV's advisories for {subject} are not a list")
        for advisory in advisories:
            identifier = advisory.get("id") if isinstance(advisory, dict) else None
            if not isinstance(identifier, str) or not identifier:
                raise CannotDecideError(f"OSV listed an advisory without an id for {subject}")
            lines.append(f"{identifier}  {subject}  {ADVISORY}{identifier}")
    return lines


def post_to_osv(body: dict[str, object]) -> object:
    """POST `body` to OSV's querybatch endpoint and return the decoded JSON."""
    with urllib.request.urlopen(
        urllib.request.Request(
            "https://api.osv.dev/v1/querybatch",
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        ),
        timeout=60,
    ) as response:
        return json.loads(response.read())


def main(
    argv: list[str] | None = None, post: Callable[[dict[str, object]], object] = post_to_osv
) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    project = Path(arguments[0]) if arguments else Path()
    try:
        audited = subjects(project)
        lines = findings(audited, post(batch_query(audited)))
    except (CannotDecideError, OSError, ValueError) as error:
        # URLError, HTTPError and timeouts are OSErrors; a body that is not
        # JSON is a ValueError.
        print(f"hex-audit: cannot decide: {error}", file=sys.stderr)
        return 2
    packages = len(audited) - 1
    if not lines:
        print(f"hex-audit: OSV.dev lists no advisory for {packages} hex packages or {audited[-1]}")
        return 0
    print("\n".join(lines))
    print(
        f"hex-audit: OSV.dev lists {len(lines)} advisories against these releases; "
        "move each pin past its fix, or record why it stays"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
