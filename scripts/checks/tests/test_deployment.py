"""Deployment guarantees, independent of a running cluster."""

import json
import shutil
from pathlib import Path

import pytest

import deployment

ROOT = Path(__file__).resolve().parents[3]


def resources():
    return json.loads((ROOT / "deploy/base/resources.json").read_text())["items"]


def test_restricted_skeleton():
    by_kind = {item["kind"]: item for item in resources()}
    assert len(by_kind) == 4
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


def test_role_grants_exactly_the_verbs_the_client_uses():
    by_kind = {item["kind"]: item for item in resources()}
    assert by_kind["Role"]["rules"] == [
        {"apiGroups": [""], "resources": ["pods"], "verbs": ["list", "patch"]}
    ]
    binding = by_kind["RoleBinding"]
    assert binding["roleRef"] == {
        "apiGroup": "rbac.authorization.k8s.io",
        "kind": "Role",
        "name": "knarr",
    }
    assert binding["subjects"] == [{"kind": "ServiceAccount", "name": "knarr"}]


def test_token_is_projected_with_the_shortest_expiry_and_read_only():
    by_kind = {item["kind"]: item for item in resources()}
    pod = by_kind["Deployment"]["spec"]["template"]["spec"]
    # Automount stays off at both levels: the projected volume is the only token.
    assert pod["automountServiceAccountToken"] is False
    assert by_kind["ServiceAccount"]["automountServiceAccountToken"] is False
    volume = next(volume for volume in pod["volumes"] if volume["name"] == "kube-api-access")
    sources = volume["projected"]["sources"]
    assert {"serviceAccountToken": {"path": "token", "expirationSeconds": 600}} in sources
    assert {
        "configMap": {"name": "kube-root-ca.crt", "items": [{"key": "ca.crt", "path": "ca.crt"}]}
    } in sources
    assert {
        "downwardAPI": {
            "items": [{"path": "namespace", "fieldRef": {"fieldPath": "metadata.namespace"}}]
        }
    } in sources
    container = pod["containers"][0]
    mount = next(
        mount for mount in container["volumeMounts"] if mount["name"] == "kube-api-access"
    )
    assert mount == {
        "name": "kube-api-access",
        "mountPath": "/var/run/secrets/kubernetes.io/serviceaccount",
        "readOnly": True,
    }
    assert {"name": "POD_NAME", "valueFrom": {"fieldRef": {"fieldPath": "metadata.name"}}} in (
        container["env"]
    )
    assert {"name": "ERL_FLAGS", "value": "-knarr s1_probe true"} in container["env"]


def test_wrong_ca_variant_only_redirects_the_ca_file():
    patch = json.loads((ROOT / "deploy/wrong-ca/patch.json").read_text())
    pod = patch["spec"]["template"]["spec"]
    assert pod["containers"][0]["env"] == [
        {"name": "KNARR_CA_FILE", "value": "/etc/knarr/wrong-ca/ca.crt"}
    ]
    assert pod["containers"][0]["volumeMounts"] == [
        {"name": "wrong-ca", "mountPath": "/etc/knarr/wrong-ca", "readOnly": True}
    ]
    assert pod["volumes"] == [{"name": "wrong-ca", "configMap": {"name": "knarr-wrong-ca"}}]
    assert deployment.variants() == ["base", "wrong-ca"]


def test_unknown_variant_is_refused():
    with pytest.raises(ValueError, match="unknown deployment variant"):
        deployment.render("production")


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
