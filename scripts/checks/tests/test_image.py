"""A failed startup must retain its diagnostics and its original failure."""

import json
import subprocess

import pytest

import image


def test_startup_failure_retains_logs_and_cleans_container(monkeypatch):
    commands = []

    def output(*arguments):
        commands.append((list(arguments), {}))
        if arguments[1:3] == ("image", "inspect"):
            return json.dumps([{"Config": {"User": "10001:10001"}}])
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
    assert ["docker", "logs", "test-container"] in [args for args, _ in commands]
    assert commands[-1] == (["docker", "rm", "--force", "test-container"], {"check": False})


def test_build_fetches_rebar_without_curl_and_matches_tool_pin():
    pins = [line.split() for line in (image.ROOT / "tools.txt").read_text().splitlines()]
    pin = next(row for row in pins if row and row[0] == "rebar3" and row[2] == "linux-64")
    dockerfile = (image.ROOT / "Dockerfile").read_text()
    assert f"ADD --checksum=sha256:{pin[4]} {pin[3]} " in dockerfile
