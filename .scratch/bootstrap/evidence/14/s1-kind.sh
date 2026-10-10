#!/bin/sh
# Ticket 14 evidence: the S1 probe on this worktree's kind cluster. Builds and
# deploys the base, then reads the pod's log until it shows a token hash, a
# changed hash, and a LIST and PATCH that succeeded after the first token's
# expiry, from one process (restartCount 0, same pod UID). Captures /version
# for ticket 35's fixture item. Nothing printed holds a token.
# Usage: sh s1-kind.sh <worktree> <empty-work-dir>   (needs network, docker)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
worktree=${1:?usage: s1-kind.sh <worktree> <work-dir>}
work=${2:?usage: s1-kind.sh <worktree> <work-dir>}
mkdir -p "$work"
cd "$worktree"
PATH="$worktree/.pixi/envs/default/bin:$worktree/.pixi/envs/cluster/bin:$worktree/.tools/bin:$PATH"
export PATH
KNARR_CLUSTER=kind; export KNARR_CLUSTER
printf 'date: %s\nhost: %s\ncommit: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(uname -sm)" "$(git rev-parse --short HEAD)"
docker version --format 'docker {{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}'

just cluster-up
just image-build
just image-check
just deploy
KUBECONFIG=$worktree/.cluster/kubeconfig; export KUBECONFIG

kubectl get --raw /version > "$work/version.json"
echo '--- /version, one line, as committed to version.json beside this script ---'
python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), separators=(",", ":"), sort_keys=True))' "$work/version.json"
python3 - "$work/version.json" <<'PY'
import json, sys
version = json.load(open(sys.argv[1]))
# The hand-written fixture in test/sans_io_example_test.gleam has major, minor
# and gitVersion as strings, and more fields than the decoder reads.
wrong = [k for k in ("major", "minor", "gitVersion") if not isinstance(version.get(k), str)]
print("ok   /version has major, minor and gitVersion as strings, as the 08 fixture assumes" if not wrong
      else f"FAIL /version field types differ from the fixture: {wrong}")
print(f"     minor={version['minor']!r} (a managed cluster may add a suffix; this one is kind)")
sys.exit(1 if wrong else 0)
PY

pod=$(kubectl get pod -l app.kubernetes.io/name=knarr --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
uid=$(kubectl get pod "$pod" -o jsonpath='{.metadata.uid}')
start=$(kubectl get pod "$pod" -o jsonpath='{.status.startTime}')
echo "pod $pod uid $uid started $start"
echo '--- token mount as the process sees it (uid 10001) ---'
kubectl exec "$pod" -- ls -lnL /var/run/secrets/kubernetes.io/serviceaccount/
kubectl exec "$pod" -- sh -c 'head -c 0 /var/run/secrets/kubernetes.io/serviceaccount/token && echo "ok   token is readable by the process uid"'

# kubelet refreshes a 600 s token at about 480 s; the first token expires at
# about 600 s. Poll for up to 14 minutes.
deadline=$(( $(date +%s) + 840 ))
while :; do
  kubectl logs --timestamps "$pod" > "$work/logs.txt"
  if python3 "$here/s1_logs.py" "$work/logs.txt" "$start" > "$work/verdict.txt" 2>&1; then
    cat "$work/verdict.txt"; break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo 'FAIL the proof did not complete within 14 minutes:'; cat "$work/verdict.txt"
    grep 's1_probe event=' "$work/logs.txt" | tail -20
    exit 1
  fi
  sleep 15
done

echo '--- every token_changed and the first and last success lines ---'
grep 's1_probe event=token_changed' "$work/logs.txt"
grep 's1_probe event=patch_annotation ' "$work/logs.txt" | sed -n '1p;$p'
echo '--- the annotation on the pod ---'
value=$(kubectl get pod "$pod" -o jsonpath='{.metadata.annotations.knarr\.io/s1-probe}')
if [ -n "$value" ]; then echo "ok   knarr.io/s1-probe=$value"; else echo 'FAIL no knarr.io/s1-probe annotation on the pod'; exit 1; fi
restarts=$(kubectl get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}')
uid_now=$(kubectl get pod "$pod" -o jsonpath='{.metadata.uid}')
if [ "$restarts" = 0 ]; then echo 'ok   restartCount 0: one process read both tokens'; else echo "FAIL restartCount $restarts"; exit 1; fi
if [ "$uid_now" = "$uid" ]; then echo 'ok   same pod UID throughout'; else echo 'FAIL the pod was replaced'; exit 1; fi
echo 's1-kind: all checks passed'
