"""The tools.txt installer (Decision 0003, "Escape hatch").

The tests serve pins from file:// URLs, which the installer accepts so that
these cases need no network. The committed tools.txt is held to https by the
last tests here.
"""

from __future__ import annotations

import hashlib
import io
import platform
import re
import subprocess
import tarfile
from pathlib import Path

import pytest

from conftest import REPOSITORY

INSTALLER = REPOSITORY / "scripts" / "install-tools.sh"
HOST = {("Darwin", "arm64"): "osx-arm64", ("Linux", "x86_64"): "linux-64"}.get(
    (platform.system(), platform.machine())
)
OTHER = "linux-64" if HOST == "osx-arm64" else "osx-arm64"
SCRIPT = b"#!/bin/sh\necho fake 1.0\n"

pytestmark = pytest.mark.skipif(HOST is None, reason="tools.txt pins no line for this host")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def archive(member_path: str, content: bytes) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as tar:
        info = tarfile.TarInfo(member_path)
        info.size = len(content)
        info.mode = 0o644
        tar.addfile(info, io.BytesIO(content))
        decoy = tarfile.TarInfo("fake-1.0/README.md")
        decoy.size = 4
        tar.addfile(decoy, io.BytesIO(b"docs"))
    return buffer.getvalue()


def install(pins: Path, destination: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["sh", str(INSTALLER), str(pins), str(destination)],
        check=False,
        capture_output=True,
        text=True,
    )


@pytest.fixture
def served(tmp_path: Path) -> Path:
    directory = tmp_path / "served"
    directory.mkdir()
    return directory


def pin(name: str, url: str, digest: str, member: str, platform_name: str | None = None) -> str:
    return f"{name} 1.0 {platform_name or HOST} {url} {digest} {member}\n"


def test_an_archive_member_is_found_by_basename_and_installed(
    served: Path, tmp_path: Path
) -> None:
    data = archive("fake-1.0-target/nested/fake", SCRIPT)
    (served / "fake.tar.gz").write_bytes(data)
    pins = tmp_path / "tools.txt"
    pins.write_text(
        "# comment\n\n" + pin("fake", (served / "fake.tar.gz").as_uri(), sha256(data), "fake")
    )
    bin_dir = tmp_path / "bin"
    result = install(pins, bin_dir)
    assert result.returncode == 0, result.stderr
    installed = bin_dir / "fake"
    assert installed.read_bytes() == SCRIPT
    assert installed.stat().st_mode & 0o111
    assert (
        subprocess.run([str(installed)], capture_output=True, text=True, check=True).stdout
        == "fake 1.0\n"
    )


def test_a_plain_download_is_installed_under_the_tool_name(served: Path, tmp_path: Path) -> None:
    (served / "rawfile").write_bytes(SCRIPT)
    pins = tmp_path / "tools.txt"
    pins.write_text(pin("fake", (served / "rawfile").as_uri(), sha256(SCRIPT), "rawfile"))
    result = install(pins, tmp_path / "bin")
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "bin" / "fake").read_bytes() == SCRIPT


def test_a_sha256_mismatch_is_refused_and_nothing_is_installed(
    served: Path, tmp_path: Path
) -> None:
    (served / "rawfile").write_bytes(SCRIPT)
    pins = tmp_path / "tools.txt"
    pins.write_text(pin("fake", (served / "rawfile").as_uri(), "0" * 64, "rawfile"))
    bin_dir = tmp_path / "bin"
    result = install(pins, bin_dir)
    assert result.returncode == 1
    assert "sha256" in result.stderr
    assert not (bin_dir / "fake").exists()


def test_a_replaced_binary_is_not_accepted_on_a_rerun(served: Path, tmp_path: Path) -> None:
    (served / "rawfile").write_bytes(SCRIPT)
    pins = tmp_path / "tools.txt"
    pins.write_text(pin("fake", (served / "rawfile").as_uri(), sha256(SCRIPT), "rawfile"))
    bin_dir = tmp_path / "bin"
    assert install(pins, bin_dir).returncode == 0
    (served / "rawfile").write_bytes(b"#!/bin/sh\necho tampered\n")
    pins.write_text(pin("fake", (served / "rawfile").as_uri(), "1" * 64, "rawfile"))
    result = install(pins, bin_dir)
    assert result.returncode == 1
    assert (bin_dir / "fake").read_bytes() == SCRIPT, (
        "a refused download must not replace the binary"
    )


def test_an_archive_without_the_member_is_refused(served: Path, tmp_path: Path) -> None:
    data = archive("fake-1.0/other", SCRIPT)
    (served / "fake.tar.gz").write_bytes(data)
    pins = tmp_path / "tools.txt"
    pins.write_text(pin("fake", (served / "fake.tar.gz").as_uri(), sha256(data), "fake"))
    result = install(pins, tmp_path / "bin")
    assert result.returncode == 1
    assert "fake" in result.stderr


def test_an_installed_pin_is_kept_offline_on_a_rerun(served: Path, tmp_path: Path) -> None:
    (served / "rawfile").write_bytes(SCRIPT)
    pins = tmp_path / "tools.txt"
    pins.write_text(pin("fake", (served / "rawfile").as_uri(), sha256(SCRIPT), "rawfile"))
    bin_dir = tmp_path / "bin"
    assert install(pins, bin_dir).returncode == 0
    (served / "rawfile").unlink()  # a rerun that downloaded would now fail
    result = install(pins, bin_dir)
    assert result.returncode == 0, result.stderr
    assert "already installed" in result.stdout


def test_a_moved_pin_reinstalls(served: Path, tmp_path: Path) -> None:
    (served / "one").write_bytes(SCRIPT)
    newer = b"#!/bin/sh\necho fake 2.0\n"
    (served / "two").write_bytes(newer)
    pins = tmp_path / "tools.txt"
    bin_dir = tmp_path / "bin"
    pins.write_text(pin("fake", (served / "one").as_uri(), sha256(SCRIPT), "one"))
    assert install(pins, bin_dir).returncode == 0
    pins.write_text(pin("fake", (served / "two").as_uri(), sha256(newer), "two"))
    assert install(pins, bin_dir).returncode == 0
    assert (bin_dir / "fake").read_bytes() == newer


def test_another_platforms_lines_are_never_fetched(tmp_path: Path) -> None:
    pins = tmp_path / "tools.txt"
    pins.write_text(pin("fake", "file:///nonexistent/fake", "0" * 64, "fake", platform_name=OTHER))
    result = install(pins, tmp_path / "bin")
    assert result.returncode == 0, result.stderr
    assert not (tmp_path / "bin" / "fake").exists()


def test_a_malformed_line_is_refused(tmp_path: Path) -> None:
    pins = tmp_path / "tools.txt"
    pins.write_text(f"fake 1.0 {HOST} https://example.invalid/fake\n")
    result = install(pins, tmp_path / "bin")
    assert result.returncode == 2


def test_a_tool_no_longer_pinned_is_removed_with_its_stamp(served: Path, tmp_path: Path) -> None:
    (served / "rawfile").write_bytes(SCRIPT)
    pins = tmp_path / "tools.txt"
    pins.write_text(pin("fake", (served / "rawfile").as_uri(), sha256(SCRIPT), "rawfile"))
    bin_dir = tmp_path / "bin"
    assert install(pins, bin_dir).returncode == 0
    # The pin moves to the other platform only, as when a tool is dropped here.
    pins.write_text(pin("fake", "file:///nonexistent/fake", "0" * 64, "fake", platform_name=OTHER))
    result = install(pins, bin_dir)
    assert result.returncode == 0, result.stderr
    assert not (bin_dir / "fake").exists()
    assert not (bin_dir / ".pins" / "fake").exists()
    assert "removed fake" in result.stdout


def test_a_binary_the_installer_never_recorded_is_left_alone(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "mine").write_bytes(SCRIPT)
    pins = tmp_path / "tools.txt"
    pins.write_text("# nothing pinned\n")
    result = install(pins, bin_dir)
    assert result.returncode == 0, result.stderr
    assert (bin_dir / "mine").read_bytes() == SCRIPT


LINE = re.compile(
    r"^(?P<name>[a-z0-9-]+) (?P<version>\S+) (?P<platform>linux-64|osx-arm64) "
    r"(?P<url>https://\S+) (?P<sha>[0-9a-f]{64}) (?P<member>\S+)$"
)


def committed_pins() -> list[re.Match[str]]:
    lines = (REPOSITORY / "tools.txt").read_text().splitlines()
    pins = [line for line in lines if line and not line.startswith("#")]
    matches = [LINE.match(line) for line in pins]
    assert all(matches), [line for line, m in zip(pins, matches, strict=True) if not m]
    return [m for m in matches if m]


def test_every_committed_pin_is_https_with_a_full_sha256() -> None:
    assert committed_pins()


def test_every_committed_tool_is_pinned_once_for_each_platform() -> None:
    seen: dict[str, list[str]] = {}
    for match in committed_pins():
        seen.setdefault(match["name"], []).append(match["platform"])
    assert {name: sorted(platforms) for name, platforms in seen.items()} == {
        name: ["linux-64", "osx-arm64"] for name in seen
    }
    assert {"rebar3", "ripsecrets", "editorconfig-checker"} <= set(seen)
