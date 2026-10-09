"""Deployment guarantees, independent of a running cluster."""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

import deployment

ROOT = Path(__file__).resolve().parents[3]


def test_restricted_skeleton():
    resources = json.loads((ROOT / "deploy/base/resources.json").read_text())["items"]
    by_kind = {item["kind"]: item for item in resources}
    assert by_kind["Role"]["rules"] == []
    assert by_kind["ServiceAccount"]["automountServiceAccountToken"] is False
    deployment = by_kind["Deployment"]["spec"]
    assert deployment["replicas"] == 1
    assert deployment["strategy"] == {"type": "Recreate"}
    pod = deployment["template"]["spec"]
    assert pod["automountServiceAccountToken"] is False
    assert pod["securityContext"]["runAsNonRoot"] is True
    container = pod["containers"][0]
    assert container["securityContext"]["readOnlyRootFilesystem"] is True
    assert container["securityContext"]["allowPrivilegeEscalation"] is False
    assert container["securityContext"]["capabilities"]["drop"] == ["ALL"]
    assert container["readinessProbe"]["httpGet"]["path"] == "/readyz"
    assert container["livenessProbe"]["httpGet"]["path"] == "/healthz"
    assert container["imagePullPolicy"] == "Never"


def test_vendored_schemas_are_plain_upstream_json():
    provenance = json.loads((deployment.SCHEMAS / "sources.json").read_text())
    for name, hashes in provenance["files"].items():
        assert set(hashes) == {"sha256"}
        json.loads((deployment.SCHEMAS / name).read_text())
    deployment.verify()


def test_changed_schema_is_refused(tmp_path):
    shutil.copytree(deployment.SCHEMAS, tmp_path, dirs_exist_ok=True)
    with (tmp_path / "role-rbac-v1.json").open("ab") as schema:
        schema.write(b" ")
    with pytest.raises(ValueError, match=r"role-rbac-v1\.json"):
        deployment.verify(tmp_path)


# kustomize v5.8.2's render of deploy/base, and the release render ticket 28's
# overlay-render.txt recorded with a pushed digest: the same text with the two
# container lines the overlay changes. YAML indents by 2, so the indent check
# is off for the fixture.
# editorconfig-checker-disable
BASE_RENDER = """\
apiVersion: v1
automountServiceAccountToken: false
kind: ServiceAccount
metadata:
  name: knarr
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: knarr
rules: []
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: knarr
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: knarr
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app.kubernetes.io/name: knarr
    spec:
      automountServiceAccountToken: false
      containers:
      - image: knarr:local
        imagePullPolicy: Never
        livenessProbe:
          httpGet:
            path: /healthz
            port: http
          periodSeconds: 5
          timeoutSeconds: 2
        name: knarr
        ports:
        - containerPort: 8080
          name: http
        readinessProbe:
          httpGet:
            path: /readyz
            port: http
          periodSeconds: 5
          timeoutSeconds: 2
        resources:
          limits:
            memory: 256Mi
          requests:
            cpu: 50m
            memory: 64Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
        volumeMounts:
        - mountPath: /tmp
          name: tmp
      securityContext:
        runAsGroup: 10001
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile:
          type: RuntimeDefault
      serviceAccountName: knarr
      volumes:
      - emptyDir: {}
        name: tmp
"""
# editorconfig-checker-enable
DIGEST = "sha256:72d620f203b377bb4c2e2e5e9e3a81cf31228d31b5d8ebb1f85e20b7f767137b"
RELEASE_RENDER = BASE_RENDER.replace(
    "      - image: knarr:local\n        imagePullPolicy: Never\n",
    f"      - image: ghcr.io/steven-cutting/knarr@{DIGEST}\n        imagePullPolicy: IfNotPresent\n",
)


def test_the_overlay_may_change_the_image_and_its_pull_policy():
    assert RELEASE_RENDER != BASE_RENDER
    assert deployment.overlay_difference(BASE_RENDER, RELEASE_RENDER) == (
        f"ghcr.io/steven-cutting/knarr@{DIGEST}"
    )


@pytest.mark.parametrize(
    ("release", "problem"),
    [
        (BASE_RENDER, "does not change"),
        (RELEASE_RENDER.replace("  replicas: 1\n", "  replicas: 2\n"), "replicas"),
        (RELEASE_RENDER.replace(f"@{DIGEST}", ":0.1.0"), "knarr:0.1.0"),
        (RELEASE_RENDER.replace(DIGEST, "sha256:72d620f2"), "sha256:72d620f2"),
        (RELEASE_RENDER.replace("steven-cutting/knarr", "someone/knarr"), "someone/knarr"),
        (RELEASE_RENDER.replace("IfNotPresent", "Always"), "Always"),
        (
            RELEASE_RENDER.replace("imagePullPolicy: IfNotPresent", "imagePullPolicy: Never"),
            "does not change imagePullPolicy",
        ),
        (
            RELEASE_RENDER + "---\napiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: knarr\n",
            "78 lines",
        ),
    ],
    ids=[
        "no change",
        "a third line",
        "pinned by tag",
        "a short digest",
        "another image",
        "another pull policy",
        "the image alone",
        "an added resource",
    ],
)
def test_the_overlay_may_change_nothing_else(release, problem):
    with pytest.raises(ValueError, match=re.escape(problem)):
        deployment.overlay_difference(BASE_RENDER, release)


PINNED = f"ghcr.io/steven-cutting/knarr@{DIGEST}"


def containers(*items):
    """A render's containers block, one (image, pull policy, name) per container."""
    return "      containers:\n" + "".join(
        f"      - image: {image}\n        imagePullPolicy: {policy}\n        name: {name}\n"
        for image, policy, name in items
    )


def test_the_overlay_may_pin_a_container_that_is_not_the_first():
    base = containers(("busybox", "Never", "sidecar"), ("knarr:local", "Never", "knarr"))
    release = containers(("busybox", "Never", "sidecar"), (PINNED, "IfNotPresent", "knarr"))
    assert deployment.overlay_difference(base, release) == PINNED


@pytest.mark.parametrize(
    "release",
    [
        containers(("busybox", "IfNotPresent", "sidecar"), (PINNED, "Never", "knarr")),
        containers((PINNED, "Never", "sidecar"), ("knarr:local", "IfNotPresent", "knarr")),
    ],
    ids=["the policy on a sidecar", "the image on a sidecar"],
)
def test_the_image_and_the_pull_policy_are_one_containers(release):
    base = containers(("busybox", "Never", "sidecar"), ("knarr:local", "Never", "knarr"))
    with pytest.raises(ValueError, match="of another"):
        deployment.overlay_difference(base, release)


def overlay_lines(name):
    """A file in deploy/release, without its comments and blank lines."""
    text = (ROOT / "deploy/release" / name).read_text()
    return [
        line for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")
    ]


def test_the_committed_overlay_pins_the_published_image_and_nothing_else():
    resources = json.loads((ROOT / "deploy/base/resources.json").read_text())["items"]
    base = next(item for item in resources if item["kind"] == "Deployment")
    container = base["spec"]["template"]["spec"]["containers"][0]
    assert "imagePullPolicy" in container
    lines = overlay_lines("kustomization.yaml")
    assert [line for line in lines if not line.startswith(" ")] == [
        "apiVersion: kustomize.config.k8s.io/v1beta1",
        "kind: Kustomization",
        "resources:",
        "images:",
        "patches:",
    ]
    assert lines[lines.index("resources:") + 1 : lines.index("images:")] == ["  - ../base"]
    images = lines[lines.index("images:") + 1 : lines.index("patches:")]
    assert len(images) == 3
    assert images[:2] == [
        f"  - name: {container['image'].partition(':')[0]}",
        "    newName: ghcr.io/steven-cutting/knarr",
    ]
    assert re.fullmatch(r"    digest: sha256:[0-9a-f]{64}", images[2])
    assert lines[lines.index("patches:") + 1 :] == [
        "  - path: pull-policy.yaml",
        "    target:",
        "      kind: Deployment",
        f"      name: {base['metadata']['name']}",
    ]
    assert overlay_lines("pull-policy.yaml") == [
        "- op: replace",
        "  path: /spec/template/spec/containers/0/imagePullPolicy",
        "  value: IfNotPresent",
    ]


def render_with_fakes(tmp_path, release):
    """`deployment.py --render` with a fake kustomize serving canned renders and a fake kubeconform."""
    renders = tmp_path / "renders"
    renders.mkdir()
    (renders / "base").write_text(BASE_RENDER)
    (renders / "release").write_text(release)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    for tool, body in [
        (
            "kustomize",
            "sys.stdout.write(open(os.path.join(os.environ['RENDERS'], os.path.basename(sys.argv[2]))).read())",
        ),
        ("kubeconform", "stdin = sys.stdin.read()"),
    ]:
        executable = binaries / tool
        executable.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "stdin = None\n"
            f"{body}\n"
            "with open(os.environ['CALL_LOG'], 'a') as f:\n"
            f"    f.write(json.dumps([{tool!r}, sys.argv[1:], stdin]) + '\\n')\n"
        )
        executable.chmod(0o755)
    log = tmp_path / "calls.jsonl"
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts/checks/deployment.py"), "--render"],
        env={
            **os.environ,
            "PATH": f"{binaries}:{os.environ['PATH']}",
            "RENDERS": str(renders),
            "CALL_LOG": str(log),
        },
        capture_output=True,
        text=True,
        check=False,
    )
    calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    return result, calls


def test_render_builds_and_validates_both_and_checks_their_difference(tmp_path):
    result, calls = render_with_fakes(tmp_path, RELEASE_RENDER)
    assert result.returncode == 0, result.stderr
    assert [arguments for tool, arguments, _ in calls if tool == "kustomize"] == [
        ["build", str(ROOT / "deploy/base")],
        ["build", str(ROOT / "deploy/release")],
    ]
    validated = [(arguments, stdin) for tool, arguments, stdin in calls if tool == "kubeconform"]
    assert [stdin for _, stdin in validated] == [BASE_RENDER, RELEASE_RENDER]
    assert all("-strict" in arguments for arguments, _ in validated)
    assert f"ghcr.io/steven-cutting/knarr@{DIGEST}" in result.stdout


def test_render_fails_when_the_overlay_changes_anything_else(tmp_path):
    result, calls = render_with_fakes(
        tmp_path, RELEASE_RENDER.replace("replicas: 1", "replicas: 2")
    )
    assert result.returncode != 0
    assert "replicas" in result.stderr
    assert [tool for tool, _, _ in calls] == [
        "kustomize",
        "kustomize",
        "kubeconform",
        "kubeconform",
    ]
