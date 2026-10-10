"""The release guards' own tests (scripts/release/lib_test.sh) run in the gate."""

import re
import subprocess

from conftest import REPOSITORY

SCRIPT = REPOSITORY / "scripts/release/lib_test.sh"


def test_the_release_guards_pass_their_shell_tests():
    result = subprocess.run(["sh", str(SCRIPT)], capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr
    assert re.fullmatch(r"\d+ passed, 0 failed", result.stdout.splitlines()[-1]), result.stdout
