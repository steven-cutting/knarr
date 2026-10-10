"""`just release-pin`: scripts/release/pin-digest.sh pins the release overlay.

Each test runs the script in a copy of deploy/ and scripts/release/, with a fake
kustomize on PATH that renders the image from the copied kustomization, so the
real overlay is never touched and no cluster tools are needed.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from conftest import REPOSITORY

DIGEST = "sha256:" + "0123456789abcdef" * 4
OTHER = "sha256:" + "fedcba9876543210" * 4
DIGEST_LINE = re.compile(r"^( *digest: )sha256:[0-9a-f]{64}$", re.MULTILINE)
FAKE_KUSTOMIZE = """\
import os, pathlib, re, sys
assert sys.argv[1] == "build", sys.argv
if os.environ.get("KUSTOMIZE_FAILS"):
    sys.exit("Error: accumulating resources")
text = (pathlib.Path(sys.argv[2]) / "kustomization.yaml").read_text()
name = re.search(r"newName: (\\S+)", text).group(1)
digest = re.search(r"digest: (\\S+)", text).group(1)
print("      containers:")
print(f"      - image: {name}@{digest}")
print("        imagePullPolicy: IfNotPresent")
"""


@pytest.fixture
def checkout(tmp_path: Path) -> Path:
    root = tmp_path / "checkout"
    shutil.copytree(REPOSITORY / "deploy", root / "deploy")
    shutil.copytree(REPOSITORY / "scripts/release", root / "scripts/release")
    binaries = tmp_path / "bin"
    binaries.mkdir()
    fake = binaries / "kustomize"
    fake.write_text(f"#!{sys.executable}\n{FAKE_KUSTOMIZE}")
    fake.chmod(0o755)
    return root


def overlay(checkout: Path) -> Path:
    return checkout / "deploy/release/kustomization.yaml"


def pin(checkout: Path, digest: str, **env: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["sh", str(checkout / "scripts/release/pin-digest.sh"), digest],
        env={**os.environ, "PATH": f"{checkout.parent / 'bin'}:{os.environ['PATH']}", **env},
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.mark.parametrize(
    "digest",
    [
        "",
        "sha256:0123",
        DIGEST.removeprefix("sha256:"),
        DIGEST.upper().replace("SHA256", "sha256"),
        f"{DIGEST}\n",
        f"{DIGEST}\n{OTHER}",
        f"{DIGEST} ",
        "sha512:" + "0" * 128,
    ],
    ids=[
        "empty",
        "short",
        "no algorithm",
        "upper case",
        "a trailing newline",
        "two lines",
        "a trailing space",
        "another algorithm",
    ],
)
def test_a_malformed_digest_is_refused(checkout: Path, digest: str) -> None:
    before = overlay(checkout).read_bytes()
    result = pin(checkout, digest)
    assert result.returncode != 0
    assert "not a digest" in result.stderr
    assert overlay(checkout).read_bytes() == before


@pytest.mark.parametrize(
    "pinned", [False, True], ids=["the committed overlay", "a pinned overlay"]
)
def test_a_digest_changes_one_line_and_prints_the_reference(checkout: Path, pinned: bool) -> None:
    if pinned:
        text = overlay(checkout).read_text()
        overlay(checkout).write_text(DIGEST_LINE.sub(rf"\g<1>{DIGEST}", text))
    before = overlay(checkout).read_text().splitlines()
    # Whatever the overlay holds now, the placeholder or a pinned digest, a new
    # digest replaces it.
    (current,) = [line for line in before if DIGEST_LINE.fullmatch(line)]
    digest = OTHER if DIGEST in current else DIGEST
    result = pin(checkout, digest)
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines()[-1] == f"ghcr.io/steven-cutting/knarr@{digest}"
    after = overlay(checkout).read_text().splitlines()
    assert len(after) == len(before)
    assert [(old, new) for old, new in zip(before, after, strict=True) if old != new] == [
        (current, DIGEST_LINE.sub(rf"\g<1>{digest}", current))
    ]
    assert sorted(path.name for path in overlay(checkout).parent.iterdir()) == [
        "kustomization.yaml",
        "pull-policy.yaml",
    ]


def test_pinning_twice_is_idempotent_and_a_new_digest_replaces_the_old(checkout: Path) -> None:
    assert pin(checkout, DIGEST).returncode == 0
    once = overlay(checkout).read_bytes()
    assert pin(checkout, DIGEST).returncode == 0
    assert overlay(checkout).read_bytes() == once
    result = pin(checkout, OTHER)
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines()[-1] == f"ghcr.io/steven-cutting/knarr@{OTHER}"
    assert overlay(checkout).read_bytes() == once.replace(DIGEST.encode(), OTHER.encode())


@pytest.mark.parametrize("count", [0, 2])
def test_an_overlay_without_exactly_one_digest_line_is_refused(checkout: Path, count: int) -> None:
    lines = overlay(checkout).read_text().splitlines(keepends=True)
    (digest_line,) = [line for line in lines if line.lstrip().startswith("digest: ")]
    index = lines.index(digest_line)
    lines[index : index + 1] = [digest_line] * count
    overlay(checkout).write_text("".join(lines))
    before = overlay(checkout).read_bytes()
    result = pin(checkout, DIGEST)
    assert result.returncode != 0
    assert f"{count} digest lines" in result.stderr
    assert overlay(checkout).read_bytes() == before


def test_a_render_that_is_not_the_pinned_reference_fails(checkout: Path) -> None:
    text = overlay(checkout).read_text()
    overlay(checkout).write_text(
        text.replace("newName: ghcr.io/steven-cutting/knarr", "newName: x")
    )
    before = overlay(checkout).read_bytes()
    result = pin(checkout, DIGEST)
    assert result.returncode != 0
    assert f"x@{DIGEST}" in result.stderr
    assert overlay(checkout).read_bytes() == before


def test_a_failed_render_leaves_the_overlay_unchanged(checkout: Path) -> None:
    before = overlay(checkout).read_bytes()
    result = pin(checkout, DIGEST, KUSTOMIZE_FAILS="1")
    assert result.returncode != 0
    assert "accumulating resources" in result.stderr
    assert overlay(checkout).read_bytes() == before
