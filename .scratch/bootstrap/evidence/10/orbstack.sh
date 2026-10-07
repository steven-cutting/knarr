#!/bin/sh
# Ticket 10 evidence: OrbStack's built-in Kubernetes as an optional local loop.
#   start   orbctl start k8s until a node is Ready and the default
#           ServiceAccount exists, three times from stopped (the cluster's
#           state persists between starts, so this is start-to-ready)
#   image   a locally built image runs with imagePullPolicy: Never and no
#           load step, because the cluster shares OrbStack's docker engine
#   reach   a pod IP and a ClusterIP answer HTTP from the Mac
#   one     one cluster per machine: one "orbstack" context, a fixed port, no
#           name to give
# It leaves k8s.enable false whatever happens (the trap), as agreed for this
# spike, and records the state it found. Starting k8s writes the "orbstack"
# context into ~/.kube/config; the hashes show it.
# Usage: sh orbstack.sh <tools-dir> <empty-work-dir>
set -eu
usage='usage: orbstack.sh <tools-dir> <empty-work-dir>'
tools=$(cd "${1:?$usage}" && pwd); work=${2:?$usage}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
PATH=$tools/bin:$tools/.pixi/envs/cluster/bin:$PATH; export PATH
KUBECONFIG=$HOME/.orbstack/k8s/config.yml; export KUBECONFIG
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
now() { perl -MTime::HiRes=time -e 'printf "%.1f\n", time'; }
since() { perl -e 'printf "%.1f\n", $ARGV[1] - $ARGV[0]' "$1" "$(now)"; }
median() { printf '%s\n' "$@" | sort -n | sed -n 2p; }
sha() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi | cut -c1-16; }
standin=knarr-standin:orbstack-$$
# Per-run names: OrbStack keeps the cluster between starts, so a pod from an
# earlier run may still be there.
pod=standin-$$; web=web-$$
busybox=busybox:1.37.0@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e
restore() {
  kubectl delete pod "$pod" "$web" --ignore-not-found --timeout=60s > /dev/null 2>&1 || true
  kubectl delete service "$web" --ignore-not-found > /dev/null 2>&1 || true
  docker rmi -f "$standin" > /dev/null 2>&1 || true
  orbctl stop k8s > /dev/null 2>&1 || true
  orbctl config set k8s.enable false > /dev/null 2>&1 || true
  printf '\n== restored: k8s.enable %s\n' "$(orbctl config get k8s.enable 2>&1)"
}
trap restore EXIT

printf 'date: %s\n%s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(orbctl version | head -1)"
initial=$(orbctl config get k8s.enable)
printf 'k8s.enable when this script started: %s\n' "$initial"
kube_before=$(sha < "$HOME/.kube/config")

ready() {
  i=0; until kubectl get nodes > /dev/null 2>&1; do i=$((i + 1)); [ "$i" -lt 600 ] || fail 'apiserver never answered'; sleep 0.2; done
  kubectl wait --for=condition=Ready node --all --timeout=180s > /dev/null
  i=0; until kubectl get serviceaccount default > /dev/null 2>&1; do i=$((i + 1)); [ "$i" -lt 600 ] || fail 'no default SA'; sleep 0.2; done
}

echo; echo '== start-to-ready, three times from stopped'
starts=
for r in 1 2 3; do
  orbctl stop k8s > /dev/null 2>&1 || true
  i=0; while kubectl get --raw /readyz > /dev/null 2>&1; do i=$((i + 1)); [ "$i" -lt 300 ] || fail 'k8s did not stop'; sleep 0.2; done
  t=$(now); orbctl start k8s > /dev/null; ready; s=$(since "$t")
  printf 'run %s: start-to-ready %ss\n' "$r" "$s"
  starts="$starts $s"
done
# shellcheck disable=SC2086  # one value per run
printf 'median %ss\n' "$(median $starts)"
kubectl version | sed -n 's/^Server Version: /server: /p'
kubectl get nodes -o custom-columns=NODE:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion --no-headers

echo; echo '== a local image, no load step'
printf 'FROM registry.k8s.io/pause:3.10@sha256:ee6521f290b2168b6e0935a181d4cff9be1ac3f505666ef0e3c98fae8199917a\n' |
  docker build -q -t "$standin" - > /dev/null
kubectl run "$pod" --image "$standin" --image-pull-policy Never --restart Never > /dev/null
kubectl wait --for=condition=Ready "pod/$pod" --timeout 60s > /dev/null || fail 'local image did not run'
echo "ok   $standin, built with docker build, runs with imagePullPolicy: Never"

echo; echo '== pod IP and ClusterIP reach from the Mac'
kubectl run "$web" --image "$busybox" --port 8080 --restart Never -- httpd -f -p 8080 -h /etc > /dev/null
kubectl wait --for=condition=Ready "pod/$web" --timeout 90s > /dev/null || fail 'web pod not Ready'
kubectl expose pod "$web" --port 80 --target-port 8080 > /dev/null
pod_ip=$(kubectl get pod "$web" -o jsonpath='{.status.podIP}')
svc_ip=$(kubectl get service "$web" -o jsonpath='{.spec.clusterIP}')
curl -fsS --max-time 10 -o /dev/null "http://$pod_ip:8080/hostname" || fail "pod IP $pod_ip unreachable from the Mac"
echo "ok   pod IP $pod_ip:8080 answers from the Mac"
curl -fsS --max-time 10 -o /dev/null "http://$svc_ip/hostname" || fail "ClusterIP $svc_ip unreachable from the Mac"
echo "ok   ClusterIP $svc_ip:80 answers from the Mac"

echo; echo '== one cluster per machine'
printf 'contexts in %s: %s\n' "${KUBECONFIG#"$HOME"/}" "$(kubectl config get-contexts -o name | tr '\n' ' ')"
printf 'apiserver: %s (fixed; every worktree would share it)\n' "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
orbctl k8s 2>&1 | grep -E 'orbctl (start|stop) k8s' | sed 's/^ */command: /'
echo 'orbctl start k8s takes no cluster name: a second worktree gets this same cluster,'
echo 'so isolation would be by namespace only.'

kube_after=$(sha < "$HOME/.kube/config")
printf '\n~/.kube/config before %s, after %s' "$kube_before" "$kube_after"
if [ "$kube_before" = "$kube_after" ]; then echo ' (unchanged)'; else echo ' (OrbStack rewrote it)'; fi
