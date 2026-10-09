"""Deployment guarantees, independent of a running cluster."""

import json
import shutil
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
