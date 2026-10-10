"""The fake worker's cluster actions (ticket 29), against fakes of kind and kubectl.

The real run is `just fake-worker-deploy` and `just fake-worker-smoke` on kind,
in CI's non-required fake-worker job; these pin what those actions ask of the
cluster and what the smoke accepts as an answer.
"""

from __future__ import annotations

import contextlib
import json
import urllib.parse
from pathlib import Path

import pytest

import cluster
from test_cluster_commands import run_fake


def test_deploy_loads_and_rolls_out_the_fake_worker(tmp_path: Path) -> None:
    result, calls = run_fake(tmp_path, "kind", "fake-worker-deploy", configured=True)
    assert result.returncode == 0, result.stderr
    commands = [call[0][1:] for call in calls]
    load = next(command for command in commands if command[:2] == ["load", "docker-image"])
    assert load[2].startswith("fake-worker:work-tree-")
    render = tmp_path / "work tree/.cluster/render/fake-worker"
    data = json.loads((render / "resources.json").read_text())
    deployments = [item for item in data["items"] if item["kind"] == "Deployment"]
    assert {item["metadata"]["name"] for item in deployments} == {
        "fake-worker",
        "fake-worker-collector",
    }
    for item in deployments:
        template = item["spec"]["template"]
        assert template["spec"]["containers"][0]["image"] == load[2]
        annotations = template["metadata"]["annotations"]
        assert annotations["knarr.dev/local-image-id"] == "sha256:changed-image"
    assert ["build", str(render)] in commands
    rollouts = [command for command in commands if command[:2] == ["rollout", "status"]]
    assert rollouts == [
        ["rollout", "status", "--namespace=kube-system", "deployment/coredns", "--timeout=120s"],
        ["rollout", "status", "deployment/fake-worker-collector", "--timeout=120s"],
        ["rollout", "status", "deployment/fake-worker", "--timeout=120s"],
    ]
    assert all(call[1] == str(tmp_path / "work tree/.cluster/kubeconfig") for call in calls)


@pytest.mark.parametrize("action", ["fake-worker-deploy", "fake-worker-smoke"])
def test_kwok_refuses_the_fake_worker(tmp_path: Path, action: str) -> None:
    result, calls = run_fake(tmp_path, "kwok", action, configured=True)
    assert result.returncode != 0
    assert "kind" in result.stderr
    assert not calls


class FakeCluster:
    """Four workers and a collector, answering as the fake worker does."""

    def __init__(self, pods: list[str]) -> None:
        self.pods = {
            pod: {"cost": 0, "accepting": True, "failure": "none", "terminating": False}
            for pod in pods
        }
        self.kills: dict[str, dict] = {"stale": {"pod": "stale"}}
        self.forwards: dict[int, tuple[str, int]] = {}
        self.commands: list[tuple[str, ...]] = []

    def output(self, *arguments: str) -> str:
        assert arguments[:3] == ("kubectl", "get", "pods")
        return " ".join(reversed(self.pods))

    def run(self, *arguments: str, **_: object) -> None:
        self.commands.append(arguments)
        if arguments[:3] == ("kubectl", "delete", "pod"):
            state = self.pods[arguments[3]]
            state["terminating"] = True
            self.kills[arguments[3]] = {
                "pod": arguments[3],
                "busy": state["cost"] > 0,
                "cost": state["cost"],
                "accepting": state["accepting"],
            }

    @contextlib.contextmanager
    def port_forward(self, _state: Path, target: str, port: int):
        local = 40000 + len(self.forwards)
        self.forwards[local] = (target, port)
        yield local

    def http(self, method: str, url: str, body: str | None = None) -> tuple[int, str]:
        target, port = self.forwards[urllib.parse.urlsplit(url).port]
        if target == "service/fake-worker-collector":
            if method == "DELETE":
                self.kills = {}
                return 204, ""
            return 200, json.dumps({"kills": list(self.kills.values())})
        state = self.pods[target.removeprefix("pod/")]
        if port == 8081:
            assert method == "PUT"
            state.update(json.loads(body or "{}"))
            return 200, "{}"
        if state["failure"] == "not_found":
            return 404, "not found\n"
        accepting = state["accepting"] and not state["terminating"]
        return 200, json.dumps({"cost": state["cost"], "accepting": accepting}).replace(" ", "")


def smoke(monkeypatch: pytest.MonkeyPatch, fake: FakeCluster, tmp_path: Path) -> None:
    for name in ("output", "run", "port_forward", "http"):
        monkeypatch.setattr(cluster, name, getattr(fake, name))
    cluster.fake_worker_smoke(tmp_path)


def test_smoke_sets_mixed_states_and_finds_both_kill_records(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    fake = FakeCluster(["w-a", "w-b", "w-c", "w-d", "w-e"])
    smoke(monkeypatch, fake, tmp_path)
    # The first four by name: idle, busy, draining and absent.
    assert [fake.pods[pod]["cost"] for pod in ["w-a", "w-b", "w-c"]] == [0, 1800, 500]
    assert fake.pods["w-d"]["failure"] == "not_found"
    assert fake.pods["w-e"] == {
        "cost": 0,
        "accepting": True,
        "failure": "none",
        "terminating": False,
    }
    assert fake.commands == [
        ("kubectl", "delete", "pod", "w-b", "--wait=false"),
        ("kubectl", "delete", "pod", "w-a", "--wait=true", "--timeout=60s"),
        ("kubectl", "wait", "--for=delete", "pod/w-b", "--timeout=60s"),
    ]
    assert set(fake.kills) == {"w-a", "w-b"}
    printed = capsys.readouterr().out
    assert "ok draining after SIGTERM w-b" in printed
    assert "ok kill record w-b: busy=true" in printed


def test_smoke_refuses_a_status_that_does_not_match(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    fake = FakeCluster(["w-a", "w-b", "w-c", "w-d"])
    answer = fake.http

    def wrong(method: str, url: str, body: str | None = None) -> tuple[int, str]:
        status, text = answer(method, url, body)
        return status, text.replace('"cost":500', '"cost":501')

    fake.http = wrong
    with pytest.raises(RuntimeError, match="w-c status"):
        smoke(monkeypatch, fake, tmp_path)


def test_smoke_needs_four_running_workers(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    with pytest.raises(RuntimeError, match="4 running fake workers needed, found 3"):
        smoke(monkeypatch, FakeCluster(["w-a", "w-b", "w-c"]), tmp_path)
