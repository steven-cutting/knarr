"""Shared fixtures for the gate checkers' tests.

The checkers run as `python3 scripts/checks/<name>.py` and import `_project` as
a sibling module, so the tests put that directory on the import path the same
way and run each script through the interpreter running the tests.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

CHECKS = Path(__file__).resolve().parent.parent
REPOSITORY = CHECKS.parent.parent
sys.path.insert(0, str(CHECKS))


def git(repository: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repository), *arguments], check=True, capture_output=True, text=True
    )
    return result.stdout


@pytest.fixture
def repository(tmp_path: Path) -> Path:
    """An empty Git repository with an identity, so tests can commit in it."""
    path = tmp_path / "repository"
    path.mkdir()
    git(path, "init", "-q", "-b", "main")
    git(path, "config", "user.name", "test")
    git(path, "config", "user.email", "test@example.invalid")
    git(path, "config", "commit.gpgsign", "false")
    return path
