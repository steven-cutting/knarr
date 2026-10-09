"""The container bounds inherited descriptor limits without raising lower ones."""

import resource
import subprocess
import sys

import pytest

from conftest import REPOSITORY


@pytest.mark.parametrize("inherited, expected", [(1024, 1024), (131072, 65536)])
def test_descriptor_limit_and_argument_forwarding(inherited, expected):
    def set_limit():
        _, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        resource.setrlimit(resource.RLIMIT_NOFILE, (inherited, hard))

    result = subprocess.run(
        [
            "bash",
            str(REPOSITORY / "scripts/container-entrypoint.sh"),
            sys.executable,
            "-c",
            (
                "import resource, sys; print(resource.getrlimit(resource.RLIMIT_NOFILE)[0]); "
                "print(sys.argv[1]); sys.exit(7)"
            ),
            "an argument with spaces",
        ],
        preexec_fn=set_limit,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 7, result.stderr
    assert result.stdout.splitlines() == [str(expected), "an argument with spaces"]
