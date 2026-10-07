"""The two prek configs: pinned remote hooks, and a read-only gate config.

prek's YAML is read line by line here, because the standard library has no YAML
parser and knarr installs no PyPI package. The configs keep one `repo:` and one
`rev:` per line, which is the layout prek itself writes.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from conftest import REPOSITORY

READ_ONLY = REPOSITORY / ".pre-commit-config.yaml"
FIX = REPOSITORY / ".pre-commit-fix.yaml"
NOT_REMOTE = {"local", "builtin", "meta"}
PINNED_REV = re.compile(r"^\s*rev:\s*[0-9a-f]{40}\s+#\s*\S*v?\d+\.\d+")


def unpinned_remote_repos(text: str) -> list[str]:
    """Every remote `repo:` whose `rev:` is not a full commit SHA with a version comment."""
    problems: list[str] = []
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.match(r"^\s*-\s*repo:\s*(\S+)", line)
        if not match or match.group(1) in NOT_REMOTE:
            continue
        rev = next(
            (later for later in lines[index + 1 :] if re.match(r"^\s*(rev:|-\s*repo:)", later)), ""
        )
        if not PINNED_REV.match(rev):
            problems.append(match.group(1))
    return problems


@pytest.mark.parametrize(
    ("config", "unpinned"),
    [
        ("repos:\n  - repo: local\n    hooks: []\n", []),
        (
            (
                "repos:\n  - repo: https://github.com/a/b\n"
                "    rev: 675b1261a4d9668c357fcd67deb87aed8b881b94 # v3.11.1\n"
            ),
            [],
        ),
        (
            "repos:\n  - repo: https://github.com/a/b\n    rev: v3.11.1\n",
            ["https://github.com/a/b"],
        ),
        (
            (
                "repos:\n  - repo: https://github.com/a/b\n"
                "    rev: 675b1261a4d9668c357fcd67deb87aed8b881b94\n"
            ),
            ["https://github.com/a/b"],
        ),
        ("repos:\n  - repo: https://github.com/a/b\n    hooks: []\n", ["https://github.com/a/b"]),
    ],
)
def test_the_pin_rule_itself(config: str, unpinned: list[str]) -> None:
    assert unpinned_remote_repos(config) == unpinned


@pytest.mark.parametrize("path", [READ_ONLY, FIX], ids=lambda p: p.name)
def test_every_remote_hook_is_pinned_to_a_full_commit_sha(path: Path) -> None:
    assert unpinned_remote_repos(path.read_text()) == []


WRITING_FLAGS = re.compile(r"--fix\b|--write\b|--write-changes\b|-w\b")
FORMATTER = re.compile(r"\b(gleam format|ruff format|taplo fmt)\b")


def test_the_read_only_config_never_repairs() -> None:
    entries = [
        line.split("entry:", 1)[1]
        for line in READ_ONLY.read_text().splitlines()
        if "entry:" in line
    ]
    assert entries
    for entry in entries:
        assert not WRITING_FLAGS.search(entry), entry
        if FORMATTER.search(entry):
            assert "--check" in entry, entry
    for fixer in ("end-of-file-fixer", "trailing-whitespace", "mixed-line-ending"):
        assert f"id: {fixer}" not in READ_ONLY.read_text()
