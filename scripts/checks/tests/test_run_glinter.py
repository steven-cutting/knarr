"""scripts/checks/run_glinter.sh, which `just lint-gleam` runs.

glinter 2.19.2 skips a file it cannot read or parse, a directory it cannot
read, and a gleam.toml it cannot parse, prints why on stderr, and still exits 0.
The wrapper fails instead. Each case runs it against a stand-in `gleam` on PATH,
so nothing here compiles or lints a real project.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from conftest import CHECKS

WRAPPER = CHECKS / "run_glinter.sh"
BARE_PATH = "/usr/bin:/bin"
SKIPPED = "glinter skipped input it could not read or parse (above); failing instead of passing"
UNAVAILABLE = "gleam is unavailable; run just initialize"


def stand_in(tmp_path: Path, *, stdout: str = "", stderr: str = "", status: int = 0) -> Path:
    """A `gleam` that records its arguments, prints what it is given, and exits."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    gleam = bin_dir / "gleam"
    gleam.write_text(
        "#!/bin/sh\n"
        f'printf \'%s\\n\' "$*" > "{tmp_path / "arguments"}"\n'
        f"printf '%s' '{stdout}'\n"
        f"printf '%s' '{stderr}' >&2\n"
        f"exit {status}\n"
    )
    gleam.chmod(0o755)
    return bin_dir


def wrap(tmp_path: Path, path: str, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["sh", str(WRAPPER), *arguments],
        cwd=tmp_path,
        env={"PATH": path},
        check=False,
        capture_output=True,
        text=True,
    )


def test_a_clean_run_passes_with_glinter_s_output(tmp_path: Path) -> None:
    bin_dir = stand_in(tmp_path, stdout="No issues found.\n")
    result = wrap(tmp_path, f"{bin_dir}:{BARE_PATH}")
    assert (result.returncode, result.stdout, result.stderr) == (0, "No issues found.\n", "")


def test_glinter_runs_through_gleam_with_the_arguments_passed_on(tmp_path: Path) -> None:
    bin_dir = stand_in(tmp_path)
    wrap(tmp_path, f"{bin_dir}:{BARE_PATH}", "--format", "json", "test/a b.gleam")
    assert (tmp_path / "arguments").read_text() == (
        "run --no-print-progress -m glinter --format json test/a b.gleam\n"
    )


def test_a_finding_keeps_glinter_s_status(tmp_path: Path) -> None:
    finding = "src/knarr.gleam:3:1: error [echo] Remove echo before committing\n"
    bin_dir = stand_in(tmp_path, stdout=finding, status=1)
    result = wrap(tmp_path, f"{bin_dir}:{BARE_PATH}")
    assert (result.returncode, result.stdout, result.stderr) == (1, finding, "")


# Every message glinter 2.19.2 prints when it skips input (src/glinter.gleam).
@pytest.mark.parametrize(
    "message",
    [
        "Error: Failed to parse test/broken.gleam",
        "Error: Could not read test/unreadable.gleam",
        "Warning: Could not read directory test/",
        "Warning: Could not parse config file, using defaults",
    ],
)
def test_skipped_input_fails_a_run_glinter_passed(tmp_path: Path, message: str) -> None:
    bin_dir = stand_in(tmp_path, stdout="No issues found.\n", stderr=f"{message}\n")
    result = wrap(tmp_path, f"{bin_dir}:{BARE_PATH}")
    assert result.returncode == 1
    assert result.stdout == "No issues found.\n"
    assert result.stderr.splitlines() == [message, SKIPPED]


def test_skipped_input_keeps_a_failing_status(tmp_path: Path) -> None:
    bin_dir = stand_in(tmp_path, stderr="Error: Failed to parse test/broken.gleam\n", status=3)
    result = wrap(tmp_path, f"{bin_dir}:{BARE_PATH}")
    assert result.returncode == 3
    assert result.stderr.splitlines()[-1] == SKIPPED


def test_a_compile_error_keeps_its_status_and_is_not_read_as_a_skip(tmp_path: Path) -> None:
    compile_error = "error: Unknown variable\n"
    bin_dir = stand_in(tmp_path, stderr=compile_error, status=1)
    result = wrap(tmp_path, f"{bin_dir}:{BARE_PATH}")
    assert (result.returncode, result.stdout, result.stderr) == (1, "", compile_error)


def test_without_gleam_the_wrapper_refuses(tmp_path: Path) -> None:
    assert shutil.which("gleam", path=BARE_PATH) is None, f"a gleam is on {BARE_PATH}"
    result = wrap(tmp_path, BARE_PATH)
    assert (result.returncode, result.stdout, result.stderr) == (2, "", f"{UNAVAILABLE}\n")
