"""A failed startup must retain its diagnostics and its original failure."""

import json
import subprocess

import pytest

import image

ENTRYPOINT = ["/opt/knarr/container-entrypoint.sh", "/opt/knarr/shipment/entrypoint.sh"]


def test_startup_failure_retains_logs_and_cleans_container(monkeypatch):
    commands = []

    def output(*arguments):
        commands.append((list(arguments), {}))
        if arguments[-1] == "ulimit -Sn":
            return "65536"
        if arguments[1:3] == ("image", "inspect"):
            return json.dumps([{"Config": {"User": "10001:10001", "Entrypoint": ENTRYPOINT}}])
        if arguments[1] == "port":
            return "127.0.0.1:49152"
        if "--detach" in arguments:
            return "test-container"
        return "29"

    def run(arguments, **kwargs):
        commands.append((arguments, kwargs))
        return subprocess.CompletedProcess(arguments, 7 if arguments[0] == "curl" else 0, "", "")

    ticks = iter([0, 31])
    monkeypatch.setattr(image, "output", output)
    monkeypatch.setattr(image.subprocess, "run", run)
    monkeypatch.setattr(image.time, "monotonic", lambda: next(ticks))
    monkeypatch.setattr(image.sys, "argv", ["image.py", "knarr:test"])
    with pytest.raises(RuntimeError, match="did not become ready"):
        image.main()
    detached = next(args for args, _ in commands if "--detach" in args)
    assert "--rm" not in detached
    # The deployment's 256 MiB limit in bytes, independently calculated.
    assert "--memory=268435456" in detached
    assert "--memory-swap=268435456" in detached
    assert "--ulimit=nofile=131072:131072" in detached
    assert ["docker", "logs", "test-container"] in [args for args, _ in commands]
    assert commands[-1] == (["docker", "rm", "--force", "test-container"], {"check": False})


def test_optional_stats_failure_does_not_fail_a_healthy_image(monkeypatch):
    def output(*arguments):
        if arguments[-1] == "ulimit -Sn":
            return "65536"
        if arguments[1:3] == ("image", "inspect"):
            return json.dumps([{"Config": {"User": "10001:10001", "Entrypoint": ENTRYPOINT}}])
        if arguments[1] == "stats":
            raise subprocess.CalledProcessError(1, arguments)
        return "29"

    monkeypatch.setattr(image, "output", output)
    monkeypatch.setattr(image, "verify_running", lambda _: None)
    monkeypatch.setattr(
        image.subprocess,
        "run",
        lambda args, **_kwargs: subprocess.CompletedProcess(args, 1),
    )
    monkeypatch.setattr(image.sys, "argv", ["image.py", "knarr:test"])
    image.main()


def test_image_cannot_bypass_the_descriptor_wrapper(monkeypatch):
    monkeypatch.setattr(
        image,
        "output",
        lambda *_: json.dumps([{"Config": {"User": "10001:10001", "Entrypoint": ENTRYPOINT[1:]}}]),
    )
    monkeypatch.setattr(image.sys, "argv", ["image.py", "knarr:test"])
    with pytest.raises(RuntimeError, match="image must use the descriptor-bounding entrypoint"):
        image.main()


def test_build_fetches_rebar_without_curl_and_matches_tool_pin():
    pins = [line.split() for line in (image.ROOT / "tools.txt").read_text().splitlines()]
    pin = next(row for row in pins if row and row[0] == "rebar3" and row[2] == "linux-64")
    dockerfile = (image.ROOT / "Dockerfile").read_text()
    assert f"ADD --checksum=sha256:{pin[4]} {pin[3]} " in dockerfile
