"""Worktree naming is a public command interface (Decision 0007)."""

import re
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "cluster-name.sh"


def name(path, field="name"):
    return subprocess.check_output(["sh", str(SCRIPT), str(path), field], text=True).strip()


def test_worktrees_and_symlinks(tmp_path):
    first = tmp_path / "a" / "same tree"
    second = tmp_path / "b" / "same tree"
    first.mkdir(parents=True)
    second.mkdir(parents=True)
    link = tmp_path / "link"
    link.symlink_to(first)
    assert re.fullmatch(r"same-tree-[0-9a-f]{8}", name(first))
    assert name(first) != name(second)
    assert name(first) == name(link)
    for field, suffix in [
        ("dir", ".cluster"),
        ("kubeconfig", ".cluster/kubeconfig"),
        ("kwok-workdir", ".cluster/kwok"),
    ]:
        assert name(first, field) == str(first.resolve() / suffix)


def test_long_and_empty_basename(tmp_path):
    for base, expected in [
        ("abcdefghijklmnopqrstuvwxyz", "abcdefghijklmnopqrstuvw"),
        ("___", "wt"),
        ("a" * 22 + "-bbbb", "a" * 22),
    ]:
        path = tmp_path / base
        path.mkdir()
        assert re.fullmatch(expected + r"-[0-9a-f]{8}", name(path))
        assert len(name(path)) <= 32


def test_invalid_input(tmp_path):
    for path, field in [(tmp_path, "invalid"), (tmp_path / "missing", "name")]:
        assert (
            subprocess.run(
                ["sh", str(SCRIPT), str(path), field], capture_output=True, check=False
            ).returncode
            != 0
        )
