"""Verify an already-built image without pulling anything from a registry."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def output(*arguments):
    return subprocess.check_output(arguments, text=True).strip()


def verify_running(container):
    port = output("docker", "port", container, "8080/tcp").rsplit(":", 1)[1]
    deadline = time.monotonic() + 30
    while True:
        probe = subprocess.run(
            [
                "curl",
                "--noproxy",
                "*",
                "--fail",
                "--silent",
                "--max-time",
                "2",
                f"http://127.0.0.1:{port}/readyz",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if probe.returncode == 0 and probe.stdout == "ok\n":
            break
        if time.monotonic() >= deadline:
            raise RuntimeError("restricted image did not become ready")
        time.sleep(0.25)
    metrics = output(
        "curl",
        "--noproxy",
        "*",
        "--fail",
        "--silent",
        "--max-time",
        "5",
        f"http://127.0.0.1:{port}/metrics",
    )
    if not re.search(r"^knarr_startups_total 1(?:\.0)?$", metrics, re.MULTILINE):
        raise RuntimeError("startup metric missing")


def main():
    image = sys.argv[1]
    pin = tomllib.loads((ROOT / "pixi.toml").read_text())["feature"]["otp"]["dependencies"][
        "erlang"
    ]
    expected = pin.removeprefix("==").split(".")[0]
    config = json.loads(output("docker", "image", "inspect", image))[0]["Config"]
    if config["User"] != "10001:10001":
        raise RuntimeError("image must declare USER 10001:10001")
    if config.get("Entrypoint") != [
        "/opt/knarr/container-entrypoint.sh",
        "/opt/knarr/shipment/entrypoint.sh",
    ]:
        raise RuntimeError("image must use the descriptor-bounding entrypoint")
    resources = json.loads((ROOT / "deploy/base/resources.json").read_text())
    deployment = next(item for item in resources["items"] if item["kind"] == "Deployment")
    memory = deployment["spec"]["template"]["spec"]["containers"][0]["resources"]["limits"][
        "memory"
    ]
    if not memory.endswith("Mi"):
        raise RuntimeError("image check expects the deployment memory limit in Mi")
    budget = int(memory.removesuffix("Mi")) * 1024 * 1024
    common = [
        "docker",
        "run",
        "--pull=never",
        "--platform=linux/amd64",
        "--read-only",
        "--cap-drop=ALL",
        "--security-opt=no-new-privileges",
        "--tmpfs=/tmp:rw,noexec,nosuid,size=16m",
        f"--memory={budget}",
        f"--memory-swap={budget}",
    ]
    descriptors = output(
        *common,
        "--rm",
        "--ulimit=nofile=131072:131072",
        "--entrypoint=/opt/knarr/container-entrypoint.sh",
        image,
        "sh",
        "-c",
        "ulimit -Sn",
    )
    if descriptors != "65536":
        raise RuntimeError(f"container did not bound its descriptor limit: {descriptors}")
    build = output(*common, "--rm", "--entrypoint=cat", image, "/opt/build-otp")
    runtime = output(
        *common,
        "--rm",
        "--entrypoint=erl",
        image,
        "-noshell",
        "-eval",
        "io:put_chars(erlang:system_info(otp_release)), halt().",
    )
    if build != expected or runtime != expected:
        raise RuntimeError(f"OTP mismatch: owner={expected}, build={build}, runtime={runtime}")
    container = output(
        *common,
        "--ulimit=nofile=131072:131072",
        "--detach",
        "--publish=127.0.0.1::8080",
        image,
    )
    try:
        verify_running(container)
        subprocess.run(
            [
                "docker",
                "stats",
                "--no-stream",
                "--format=memory usage / limit: {{.MemUsage}}",
                container,
            ],
            check=False,
        )
        print(f"image: OTP {expected}, numeric user and read-only runtime verified")
    except Exception:
        subprocess.run(["docker", "inspect", "--format={{json .State}}", container], check=False)
        subprocess.run(["docker", "logs", container], check=False)
        raise
    finally:
        subprocess.run(["docker", "rm", "--force", container], check=False)


if __name__ == "__main__":
    main()
