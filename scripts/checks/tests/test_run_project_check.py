"""The read-only gate's snapshot contract (Decision 0004, "The snapshot guarantee").

Each test builds a throwaway repository whose Justfile holds recipes that pass,
fail or write, and runs the copied runner in it the way `just check` does.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from conftest import CHECKS, git

RUNNER = CHECKS / "run_project_check.py"


def justfile(runner: Path) -> str:
    """A Justfile whose check-clean calls `runner`, quoted so a path may hold spaces."""
    return f"""\
set positional-arguments := true
set shell := ["sh", "-eu", "-c"]

ok:
    true

fails:
    exit 3

writes-tracked:
    printf 'changed\\n' > tracked.txt

writes-untracked:
    printf 'new\\n' > new.txt

writes-ignored:
    mkdir -p build && printf 'output\\n' > build/out.txt

writes-and-fails:
    printf 'changed\\n' > tracked.txt && exit 4

chmods:
    chmod +x tracked.txt

stages:
    git add untracked.txt

relinks:
    ln -sf other link

check-clean baseline="":
    {shlex.quote(sys.executable)} {shlex.quote(str(runner))} clean "$1"
"""


@pytest.fixture
def gate(repository: Path) -> Path:
    (repository / "Justfile").write_text(justfile(RUNNER))
    (repository / ".gitignore").write_text("build/\n")
    (repository / "tracked.txt").write_text("tracked\n")
    (repository / "link").symlink_to("target")
    git(repository, "add", ".")
    git(repository, "commit", "-qm", "seed")
    (repository / "untracked.txt").write_text("untracked\n")
    return repository


def run(repository: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(RUNNER), *arguments],
        cwd=repository,
        check=False,
        capture_output=True,
        text=True,
    )


def test_passing_recipes_pass_and_end_with_check_clean(gate: Path) -> None:
    result = run(gate, "run", "ok", "ok")
    assert result.returncode == 0, result.stderr
    assert result.stdout.count("==> just ok") == 2
    assert "==> just check-clean" in result.stdout
    assert "worktree is unchanged" in result.stdout


def test_a_checkout_path_with_a_space_still_passes(gate: Path, tmp_path: Path) -> None:
    # The runner lives in the checkout, so check-clean names it by an absolute
    # path, which a checkout under "/work/My Project" would split.
    spaced = tmp_path / "checkout with space"
    spaced.mkdir()
    for name in ("run_project_check.py", "_project.py"):
        shutil.copy(CHECKS / name, spaced / name)
    runner = spaced / "run_project_check.py"
    (gate / "Justfile").write_text(justfile(runner))
    git(gate, "commit", "-qam", "use the spaced runner")
    result = subprocess.run(
        [sys.executable, str(runner), "run", "ok"],
        cwd=gate,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert "matches the check baseline" in result.stdout


def test_run_with_no_recipes_refuses(gate: Path) -> None:
    result = run(gate, "run")
    assert result.returncode == 2
    assert "==> just" not in result.stdout
    assert "no recipes" in result.stderr


def test_a_recipe_that_writes_a_tracked_file_fails_even_on_exit_zero(gate: Path) -> None:
    result = run(gate, "run", "writes-tracked", "ok")
    assert result.returncode == 1
    assert "just writes-tracked changed the worktree" in result.stderr
    assert "changed: tracked.txt" in result.stderr
    assert "==> just ok" not in result.stdout, "the runner must abort on the first change"


def test_a_recipe_that_adds_an_untracked_unignored_file_fails(gate: Path) -> None:
    result = run(gate, "run", "writes-untracked")
    assert result.returncode == 1
    assert "changed: new.txt" in result.stderr


def test_writing_an_ignored_path_is_allowed(gate: Path) -> None:
    result = run(gate, "run", "writes-ignored")
    assert result.returncode == 0, result.stderr


def test_a_failing_recipe_returns_its_own_status(gate: Path) -> None:
    result = run(gate, "run", "ok", "fails", "ok")
    assert result.returncode == 3
    assert result.stdout.count("==> just ok") == 1


def test_a_change_outranks_the_recipe_status(gate: Path) -> None:
    result = run(gate, "run", "writes-and-fails")
    assert result.returncode == 1
    assert "changed: tracked.txt" in result.stderr


def test_a_mode_change_is_a_change(gate: Path) -> None:
    result = run(gate, "run", "chmods")
    assert result.returncode == 1
    assert "changed: tracked.txt" in result.stderr


def test_a_change_to_the_index_is_a_change(gate: Path) -> None:
    result = run(gate, "run", "stages")
    assert result.returncode == 1
    assert "changed: status" in result.stderr


def test_a_symlink_is_hashed_by_its_target_and_never_followed(gate: Path) -> None:
    result = run(gate, "run", "relinks")
    assert result.returncode == 1
    assert "changed: link" in result.stderr


def test_the_runner_does_not_refresh_the_index(gate: Path) -> None:
    # A stat-only change makes `git status` want to rewrite the index. With
    # GIT_OPTIONAL_LOCKS=0 the snapshot must leave .git/index untouched.
    tracked = gate / "tracked.txt"
    os.utime(tracked, (1, 1))
    index = gate / ".git" / "index"
    before = index.read_bytes()
    result = run(gate, "run", "ok")
    assert result.returncode == 0, result.stderr
    assert index.read_bytes() == before


def test_clean_without_a_baseline_accepts_a_clean_worktree(gate: Path) -> None:
    (gate / "untracked.txt").unlink()
    result = run(gate, "clean")
    assert result.returncode == 0, result.stderr


def test_clean_without_a_baseline_refuses_uncommitted_work(gate: Path) -> None:
    result = run(gate, "clean", "")
    assert result.returncode == 1
    assert "not clean" in result.stderr


def test_clean_without_a_commit_accepts_the_current_state(repository: Path) -> None:
    (repository / "file.txt").write_text("x\n")
    result = run(repository, "clean")
    assert result.returncode == 0, result.stderr
    assert "No commit exists yet" in result.stdout


def test_clean_with_a_baseline_compares_against_it(gate: Path, tmp_path: Path) -> None:
    baseline = tmp_path / "baseline.json"
    # A baseline that names a different digest for a path is a change.
    baseline.write_text(json.dumps({"::status": "", "tracked.txt": "missing"}))
    result = run(gate, "clean", str(baseline))
    assert result.returncode == 1
    assert "changed: tracked.txt" in result.stderr


def test_outside_a_worktree_the_runner_refuses(tmp_path: Path) -> None:
    outside = tmp_path / "outside"
    outside.mkdir()
    environment = {**os.environ, "GIT_CEILING_DIRECTORIES": str(tmp_path)}
    result = subprocess.run(
        [sys.executable, str(RUNNER), "run", "ok"],
        cwd=outside,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 2


def test_an_unknown_mode_prints_usage(gate: Path) -> None:
    result = run(gate, "bogus")
    assert result.returncode == 2
    assert "usage" in result.stderr
