"""Hooks install only from the primary checkout (ticket 03).

Every linked worktree shares the primary checkout's .git/hooks, and prek writes
a shim that names an absolute path into whichever worktree ran it. A hook
installed from a linked worktree would break every commit once that worktree
is deleted, so a linked worktree skips the step with a notice and succeeds.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

from conftest import REPOSITORY, git

SCRIPT = REPOSITORY / "scripts" / "install-hooks.sh"


@pytest.fixture
def prek(tmp_path: Path) -> tuple[Path, Path]:
    """A stand-in prek that records each call, and the file it records to."""
    stubs = tmp_path / "stubs"
    stubs.mkdir()
    calls = tmp_path / "prek-calls"
    (stubs / "prek").write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{calls}"\n')
    (stubs / "prek").chmod(0o755)
    return stubs, calls


def install(directory: Path, stubs: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["sh", str(SCRIPT)],
        cwd=directory,
        env={**os.environ, "PATH": f"{stubs}:{os.environ['PATH']}"},
        check=False,
        capture_output=True,
        text=True,
    )


@pytest.fixture
def committed(repository: Path) -> Path:
    (repository / "README.md").write_text("seed\n")
    git(repository, "add", ".")
    git(repository, "commit", "-qm", "seed")
    return repository


def test_the_primary_checkout_installs_the_hooks(committed: Path, prek: tuple[Path, Path]) -> None:
    stubs, calls = prek
    result = install(committed, stubs)
    assert result.returncode == 0, result.stderr
    assert calls.read_text().splitlines() == ["install --overwrite --hook-type pre-commit"]


def test_a_subdirectory_of_the_primary_checkout_installs_the_hooks(
    committed: Path, prek: tuple[Path, Path]
) -> None:
    stubs, calls = prek
    (committed / "sub").mkdir()
    assert install(committed / "sub", stubs).returncode == 0
    assert calls.exists()


def test_a_linked_worktree_skips_with_a_notice_and_succeeds(
    committed: Path, prek: tuple[Path, Path], tmp_path: Path
) -> None:
    stubs, calls = prek
    linked = tmp_path / "linked"
    git(committed, "worktree", "add", "-q", "-b", "99-linked", str(linked))
    result = install(linked, stubs)
    assert result.returncode == 0, result.stderr
    assert not calls.exists(), "prek must not run from a linked worktree"
    assert "linked worktree" in result.stderr
    assert "primary checkout" in result.stderr
