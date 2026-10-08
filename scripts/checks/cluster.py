"""Per-worktree cluster adapters, invoked only through the Justfile."""

from __future__ import annotations

import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
KIND_NODE = (
    "kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0"
)
KWOK_IMAGES = {
    "kube-apiserver": "registry.k8s.io/kube-apiserver:v1.35.5@sha256:51f1971bebe13f376d648e8e42d6949a05d1f2cacbafae50245d0c58bc84997f",
    "kube-controller-manager": "registry.k8s.io/kube-controller-manager:v1.35.5@sha256:4c8d90d21b29e25486d8d33be40416de0f121f63a316ca620e9cca2ac7ec5ebd",
    "kube-scheduler": "registry.k8s.io/kube-scheduler:v1.35.5@sha256:c8e2abd96d0206ac5d863ac1f61f8bd0067e9b001ee5b1de768a68f1b9f187ff",
    "etcd": "registry.k8s.io/etcd:3.6.10-0@sha256:f65c61039e7b7fd6e651f7ec2459b880589892cb13cf79c2f71c92aa08fc5144",
    "kwok-controller": "registry.k8s.io/kwok/kwok:v0.8.0@sha256:6d25aa8fbdfe78845423160bf125b5513f9522e2770981f0945c2a250c2b26f0",
}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def output(*args):
    return run(*args, capture_output=True).stdout.strip()


def eventually(command, timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = subprocess.run(command, check=False, capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            return
        time.sleep(0.5)
    raise RuntimeError(f"Timed out: {command}")


def ready():
    eventually(["kubectl", "get", "nodes", "-o", "name", "--request-timeout=5s"])
    run("kubectl", "wait", "--for=condition=Ready", "node", "--all", "--timeout=180s")
    eventually(
        ["kubectl", "get", "serviceaccount", "default", "-o", "name", "--request-timeout=5s"]
    )


def smoke(state):
    # kubectl asks the OS to allocate its listening port, avoiding a probe/bind race.
    with (state / "port-forward.log").open("w+") as log:
        forward = subprocess.Popen(
            ["kubectl", "port-forward", "--address=127.0.0.1", "deployment/knarr", ":8080"],
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            deadline = time.monotonic() + 30
            port = None
            while time.monotonic() < deadline and forward.poll() is None:
                log.seek(0)
                match = re.search(r"Forwarding from 127\.0\.0\.1:(\d+)", log.read())
                if match:
                    port = match[1]
                    break
                time.sleep(0.1)
            if port is None:
                raise RuntimeError("port-forward failed; see .cluster/port-forward.log")
            for endpoint in ["healthz", "readyz", "metrics"]:
                body = output(
                    "curl",
                    "--noproxy",
                    "*",
                    "--fail",
                    "--silent",
                    "--show-error",
                    "--max-time",
                    "5",
                    f"http://127.0.0.1:{port}/{endpoint}",
                )
                if endpoint == "metrics":
                    if not re.search(r"^knarr_startups_total 1(?:\.0)?$", body, re.MULTILINE):
                        raise RuntimeError("startup counter missing or incorrect")
                    if "erlang_vm_" not in body:
                        raise RuntimeError("VM collectors missing")
                elif body != "ok":
                    raise RuntimeError(f"unexpected /{endpoint} response: {body!r}")
                print(f"ok /{endpoint}")
        finally:
            forward.terminate()
            try:
                forward.wait(timeout=5)
            except subprocess.TimeoutExpired:
                forward.kill()
                forward.wait()


def main():
    action, checkout = sys.argv[1:3]
    checkout = Path(checkout).resolve()
    runner = os.environ.get("KNARR_CLUSTER", "kind")
    if runner not in {"kind", "kwok"}:
        raise ValueError("KNARR_CLUSTER must be kind or kwok")
    if runner != "kind" and action in {"deploy", "smoke", "image-load"}:
        raise ValueError(f"{action} requires kind; kwok pods do not run containers")
    name = output("sh", str(ROOT / "scripts/cluster-name.sh"), str(checkout), "name")
    state = checkout / ".cluster"
    marker = state / "runner"
    if marker.exists() and marker.read_text().strip() != runner:
        raise ValueError(
            "run cluster-down with the previous KNARR_CLUSTER before changing runners"
        )
    if action not in {"up", "down"} and not (state / "kubeconfig").is_file():
        raise ValueError("local kubeconfig missing; run cluster-up first")
    os.environ.pop("KUBERNETES_SERVICE_HOST", None)
    os.environ.pop("KUBERNETES_SERVICE_PORT", None)
    os.environ["KUBECONFIG"] = str(state / "kubeconfig")
    os.environ["KWOK_WORKDIR"] = str(state / "kwok")
    os.environ["KWOK_KUBE_VERSION"] = "v1.35.5"
    image = sys.argv[3] if len(sys.argv) > 3 else f"knarr:{name}"
    if action == "down":
        run(
            "kind" if runner == "kind" else "kwokctl",
            "delete",
            "cluster",
            "--name",
            name,
            "--kubeconfig",
            os.environ["KUBECONFIG"],
        )
        if state.exists():
            shutil.rmtree(state)
    elif action == "up":
        state.mkdir(exist_ok=True, mode=0o700)
        marker.write_text(runner)
        if runner == "kind":
            existing = output("kind", "get", "clusters").splitlines()
            if name not in existing:
                run(
                    "kind",
                    "create",
                    "cluster",
                    "--name",
                    name,
                    "--image",
                    KIND_NODE,
                    "--kubeconfig",
                    os.environ["KUBECONFIG"],
                    "--wait",
                    "180s",
                )
            else:
                run(
                    "kind",
                    "export",
                    "kubeconfig",
                    "--name",
                    name,
                    "--kubeconfig",
                    os.environ["KUBECONFIG"],
                )
        else:
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = str(sock.getsockname()[1])
            images = [
                argument
                for key, value in KWOK_IMAGES.items()
                for argument in (f"--{key}-image", value)
            ]
            run(
                "kwokctl",
                "create",
                "cluster",
                "--name",
                name,
                "--runtime",
                "docker",
                "--kubeconfig",
                os.environ["KUBECONFIG"],
                "--kube-apiserver-port",
                port,
                "--wait",
                "180s",
                *images,
            )
            run("kwokctl", "scale", "node", "--name", name, "--replicas", "1")
        ready()
    elif action == "ready":
        ready()
    elif action == "image-load":
        run("kind", "load", "docker-image", image, "--name", name)
    elif action == "deploy":
        run("kind", "load", "docker-image", image, "--name", name)
        render = state / "render"
        render.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "deploy/base/resources.json").read_text())
        deployment = next(item for item in data["items"] if item["kind"] == "Deployment")
        deployment["spec"]["template"]["spec"]["containers"][0]["image"] = image
        deployment["spec"]["template"]["metadata"].setdefault("annotations", {})[
            "knarr.dev/local-image-id"
        ] = output("docker", "image", "inspect", "--format={{.Id}}", image)
        (render / "resources.json").write_text(json.dumps(data))
        shutil.copyfile(ROOT / "deploy/base/kustomization.yaml", render / "kustomization.yaml")
        rendered = output("kustomize", "build", str(render))
        run("kubectl", "apply", "-f", "-", input=rendered)
        run("kubectl", "rollout", "status", "deployment/knarr", "--timeout=120s")
    elif action == "smoke":
        smoke(state)
    elif action == "diagnostics":
        for args in [
            ("get", "pods", "-o", "wide"),
            ("describe", "deployment/knarr"),
            ("logs", "deployment/knarr", "--all-containers", "--tail=100"),
            ("get", "events", "--sort-by=.lastTimestamp"),
        ]:
            subprocess.run(["kubectl", *args], check=False)
    else:
        raise ValueError(f"unknown cluster action: {action}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"cluster: {error}", file=sys.stderr)
        sys.exit(1)
