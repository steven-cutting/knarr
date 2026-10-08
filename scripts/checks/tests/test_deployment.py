"""Deployment guarantees, independent of a running cluster."""

import json
from pathlib import Path

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
