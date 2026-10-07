"""Run every gate and prove the run did not touch the worktree.

A check that rewrites files hides drift instead of reporting it, so the runner
snapshots the repository before the first recipe and compares after each one.

Copied from github.com/steven-cutting/biscuit_games_tooling at v0.3.0
(6c5c07f6bec86e86b3930dfa41392e4b440e8c85),
src/biscuit_games_tooling/run_project_check.py. The snapshot is unchanged. The
one adaptation (Decision 0004): the recipes come from the arguments of `run`,
which the Justfile's `check` recipe passes, not from a configuration file, and
`run` with no recipes refuses, so a gate that ran nothing cannot pass.

SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import _project


def _git(
    project_root: Path, *arguments: str, check: bool = True
) -> subprocess.CompletedProcess[bytes]:
    environment = {**os.environ, "GIT_OPTIONAL_LOCKS": "0"}
    result = subprocess.run(
        ["git", *arguments],
        cwd=project_root,
        env=environment,
        check=False,
        capture_output=True,
    )
    if check and result.returncode != 0:
        detail = result.stderr.decode(errors="backslashreplace").strip()
        raise RuntimeError(detail or f"git {' '.join(arguments)} failed")
    return result


def _inside_worktree(project_root: Path) -> bool:
    result = _git(project_root, "rev-parse", "--is-inside-work-tree", check=False)
    return result.returncode == 0 and result.stdout.strip() == b"true"


def _tracked_paths(project_root: Path) -> tuple[bytes, ...]:
    output = _git(
        project_root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"
    ).stdout
    return tuple(item for item in output.split(b"\0") if item)


def _digest(project_root: Path, relative: bytes) -> str:
    path = project_root / os.fsdecode(relative)
    try:
        metadata = path.lstat()
    except OSError:
        return "missing"
    if path.is_symlink():
        return "symlink:" + hashlib.sha256(os.fsencode(path.readlink())).hexdigest()
    if not path.is_file():
        return "special"
    with path.open("rb") as stream:
        return f"{metadata.st_mode:o}:{hashlib.file_digest(stream, 'sha256').hexdigest()}"


def _snapshot(project_root: Path) -> dict[str, str]:
    status = _git(project_root, "status", "--porcelain=v1", "-z", "--untracked-files=all").stdout
    snapshot = {"::status": status.decode(errors="backslashreplace")}
    for relative in _tracked_paths(project_root):
        snapshot[os.fsdecode(relative)] = _digest(project_root, relative)
    return snapshot


def _report(before: dict[str, str], after: dict[str, str], context: str) -> None:
    print(f"\n{context} changed the worktree; checks must be read-only.", file=sys.stderr)
    for key in sorted(set(before) | set(after)):
        if before.get(key) != after.get(key):
            label = "status" if key == "::status" else key
            print(f"  changed: {label}", file=sys.stderr)


def _run(project_root: Path, recipe: str, *arguments: str) -> int:
    print(f"\n==> just {recipe}", flush=True)
    return subprocess.run(["just", recipe, *arguments], cwd=project_root, check=False).returncode


def _run_all(project_root: Path, recipes: tuple[str, ...]) -> int:
    if not _inside_worktree(project_root):
        print("just check needs a Git worktree; run just initialize", file=sys.stderr)
        return 2
    if not recipes:
        print("run: no recipes given; a gate that runs nothing cannot pass", file=sys.stderr)
        return 2

    baseline = _snapshot(project_root)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", suffix=".json", delete=False
    ) as stream:
        json.dump(baseline, stream, sort_keys=True)
        baseline_path = Path(stream.name)

    try:
        for recipe in (*recipes, "check-clean"):
            arguments = (str(baseline_path),) if recipe == "check-clean" else ()
            returncode = _run(project_root, recipe, *arguments)
            current = _snapshot(project_root)
            if current != baseline:
                _report(baseline, current, f"just {recipe}")
                return 1
            if returncode != 0:
                return returncode if returncode > 0 else 1
    finally:
        baseline_path.unlink(missing_ok=True)

    print("\nAll checks passed and the worktree is unchanged.")
    return 0


def _check_clean(project_root: Path, baseline_path: Path | None) -> int:
    if not _inside_worktree(project_root):
        print("check-clean needs a Git worktree; run just initialize", file=sys.stderr)
        return 2

    current = _snapshot(project_root)
    if baseline_path is not None:
        baseline: dict[str, str] = json.loads(baseline_path.read_text(encoding="utf-8"))
        if current != baseline:
            _report(baseline, current, "just check-clean")
            return 1
        print("The worktree matches the check baseline.")
        return 0

    if _git(project_root, "rev-parse", "--verify", "--quiet", "HEAD", check=False).returncode != 0:
        print("No commit exists yet; accepting the current state.")
        return 0
    if current["::status"]:
        print(current["::status"], file=sys.stderr)
        print("The Git worktree is not clean.", file=sys.stderr)
        return 1
    print("The Git worktree is clean.")
    return 0


def main() -> int:
    """Dispatch the aggregate runner or the standalone cleanliness assertion."""
    arguments = sys.argv[1:]
    if arguments[:1] == ["run"]:
        return _run_all(_project.root(), tuple(arguments[1:]))
    if arguments[:1] == ["clean"]:
        given = arguments[1] if len(arguments) > 1 and arguments[1] else None
        return _check_clean(_project.root(), Path(given) if given else None)
    print("usage: run_project_check.py {run <recipe>...|clean [baseline]}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
