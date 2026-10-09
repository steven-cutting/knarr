"""The container bounds inherited descriptor limits without raising lower ones."""

import resource
import subprocess
import sys

import pytest

from conftest import REPOSITORY


def test_lower_descriptor_limit_and_argument_forwarding():
    def set_limit():
        _, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        resource.setrlimit(resource.RLIMIT_NOFILE, (1024, hard))

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
    assert result.stdout.splitlines() == ["1024", "an argument with spaces"]


@pytest.mark.parametrize("inherited", ["131072", "unlimited"])
def test_high_limit_branch_without_raising_the_hosts_hard_limit(inherited):
    # The real high-limit test runs in Docker through just image-check. A shell
    # stand-in covers both branch inputs even on runners with a low hard limit.
    shell = """
        initial=$1
        script=$2
        shift 2
        ulimit() {
            if [ "$#" -eq 1 ]; then
                printf '%s\\n' "$initial"
            else
                export RECORDED_LIMIT=$2
            fi
        }
        . "$script"
    """
    result = subprocess.run(
        [
            "bash",
            "-c",
            shell,
            "test",
            inherited,
            str(REPOSITORY / "scripts/container-entrypoint.sh"),
            sys.executable,
            "-c",
            "import os; print(os.environ['RECORDED_LIMIT'])",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == "65536\n"
