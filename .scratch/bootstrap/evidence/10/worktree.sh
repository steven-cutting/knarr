#!/bin/sh
# Ticket 10 evidence: many worktrees, one cluster each, at the same time.
# For each runner, three synthetic worktrees get clusters created concurrently
# through cluster.sh (names from name.sh, KUBECONFIG and kwok's workdir under
# the worktree, no fixed host port):
#   one/knarr and two/knarr   share a basename, so the names differ only by hash
#   three/<long basename>     a 32-character name, name.sh's cap (k3d's limit)
# Then it shows: each apiserver on its own host port; each kubeconfig holds
# one context and reaches only its own cluster (a ConfigMap written through
# it names the cluster, and is read back through every kubeconfig); a local
# image loads into every cluster and runs with imagePullPolicy: Never; delete
# leaves no container, network or volume. The files a tool would write by
# default (~/.kube/config, ~/.kwok, ~/.k3d, ~/.config/k3d) are hashed before
# and after. The worktrees are plain directories: no `git worktree add` runs.
# Usage: sh worktree.sh <tools-dir> <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
usage='usage: worktree.sh <tools-dir> <empty-work-dir>'
tools=$(cd "${1:?$usage}" && pwd); work=${2:?$usage}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
PATH=$tools/bin:$tools/.pixi/envs/cluster/bin:$PATH; export PATH
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
nm() { sh "$here/name.sh" "$1" "$2"; }
standin=knarr-standin:worktree-$$
long=knarr-feature-alongbranchname-v2
trees="$work/one/knarr $work/two/knarr $work/three/$long"
runner=
cleanup() {
  if [ -n "$runner" ]; then
    for wt in $trees; do sh "$here/cluster.sh" "$tools" "$runner" down "$wt" > /dev/null 2>&1 || true; done
  fi
  docker rmi -f "$standin" > /dev/null 2>&1 || true
}
trap cleanup EXIT
sha() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi | cut -c1-16; }
fingerprint() { # a hash of a file, or of a tree's names and contents; or "absent"
  if [ -f "$1" ]; then sha < "$1"
  elif [ -d "$1" ]; then (cd "$1" && { find . | LC_ALL=C sort; find . -type f -exec cat {} +; } | sha)
  else echo absent; fi
}
outside() { for p in "$HOME/.kube/config" "$HOME/.kwok" "$HOME/.k3d" "$HOME/.config/k3d"; do printf '%s %s\n' "$p" "$(fingerprint "$p")"; done; }
# Runs cluster.sh for every tree at once; fails unless all succeed.
all() { # runner action [image]
  pids=; for wt in $trees; do
    sh "$here/cluster.sh" "$tools" "$1" "$2" "$wt" ${3:+"$3"} > "$wt.$2.log" 2>&1 & pids="$pids $!"
  done
  rc=0; for p in $pids; do wait "$p" || rc=1; done
  [ "$rc" -eq 0 ] || { for wt in $trees; do cat "$wt.$2.log"; done; fail "$1 $2 failed for a worktree"; }
}

printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
for wt in $trees; do mkdir -p "$wt"; printf '%-44s -> %s (%s chars)\n' "${wt#"$work"/}" "$(nm "$wt" name)" "$(nm "$wt" name | tr -d '\n' | wc -c | tr -d ' ')"; done
before=$(outside)
echo; echo '== outside the worktrees, before'; printf '%s\n' "$before"

printf 'FROM registry.k8s.io/pause:3.10@sha256:ee6521f290b2168b6e0935a181d4cff9be1ac3f505666ef0e3c98fae8199917a\n' |
  docker build -q -t "$standin" - > /dev/null

for runner in kind k3d kwokctl envtest; do
  echo; echo "== $runner: three clusters created concurrently"
  all "$runner" up
  ports=
  for wt in $trees; do
    kc=$(nm "$wt" kubeconfig); n=$(nm "$wt" name)
    contexts=$(KUBECONFIG=$kc kubectl config get-contexts -o name | wc -l | tr -d ' ')
    [ "$contexts" -eq 1 ] || fail "$kc holds $contexts contexts"
    server=$(KUBECONFIG=$kc kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    ports="$ports ${server##*:}"
    KUBECONFIG=$kc kubectl create configmap whoami --from-literal "cluster=$n" > /dev/null
    printf '%-34s %-26s kubeconfig %s\n' "$n" "$server" "${kc#"$work"/}"
  done
  # shellcheck disable=SC2086  # one port per line
  dups=$(printf '%s\n' $ports | sort | uniq -d)
  [ -z "$dups" ] || fail "host port shared: $dups"
  echo 'ok   every apiserver has its own host port, and every kubeconfig one context'
  # Where docker publishes the apiserver: kind and k3d use 127.0.0.1 only.
  n1=$(nm "$work/one/knarr" name)
  case $runner in
    kind) c=$n1-control-plane;; k3d) c=k3d-$n1-server-0;; kwokctl) c=kwok-$n1-kube-apiserver;; *) c=;;
  esac
  [ -z "$c" ] || printf 'host binding of %s: %s\n' "$c" "$(docker port "$c" 6443/tcp | tr '\n' ' ')"
  for wt in $trees; do
    n=$(nm "$wt" name)
    got=$(KUBECONFIG=$(nm "$wt" kubeconfig) kubectl get configmap whoami -o jsonpath='{.data.cluster}')
    [ "$got" = "$n" ] || fail "$(nm "$wt" kubeconfig) reached $got, not $n"
  done
  echo 'ok   each kubeconfig reaches its own cluster: whoami read back names it, three times'
  case $runner in
    kind|k3d)
      all "$runner" load "$standin"
      for wt in $trees; do
        KUBECONFIG=$(nm "$wt" kubeconfig) kubectl run standin --image "$standin" --image-pull-policy Never --restart Never > /dev/null
      done
      for wt in $trees; do
        KUBECONFIG=$(nm "$wt" kubeconfig) kubectl wait --for=condition=Ready pod/standin --timeout 180s > /dev/null || fail "standin not Ready in $(nm "$wt" name)"
      done
      echo "ok   $standin loaded concurrently into all three and runs with imagePullPolicy: Never";;
    kwokctl) echo 'n/a  image load: kwok pods never run';;
    envtest) echo 'n/a  image load: envtest has no kubelet';;
  esac
  all "$runner" down
  for wt in $trees; do
    n=$(nm "$wt" name)
    left=$(docker ps -a -q --filter "name=$n" | wc -l | tr -d ' ')
    nets=$(docker network ls -q --filter "name=$n" | wc -l | tr -d ' ')
    vols=$(docker volume ls -q --filter "name=$n" | wc -l | tr -d ' ')
    [ "$left$nets$vols" = 000 ] || fail "$n left $left containers, $nets networks, $vols volumes"
    [ ! -e "$(nm "$wt" dir)" ] || fail "$(nm "$wt" dir) not removed"
  done
  echo 'ok   deleted concurrently: no container, network, volume or state dir left'
done
runner=

echo; echo "== control: kwokctl's own default port, two clusters created at once"
# Why cluster.sh passes --kube-apiserver-port: kwokctl's default is the first
# free port counting down from 32766, chosen before either container binds it.
# Recorded, not asserted: the race can go either way.
ctl=$work/control; mkdir -p "$ctl"
for x in a b; do
  KWOK_WORKDIR=$ctl/kwok KWOK_KUBE_VERSION=v1.35.5 kwokctl create cluster --name "control-$x-$$" --runtime docker \
    --kubeconfig "$ctl/kubeconfig-$x" > "$ctl/$x.log" 2>&1 &
done
wait || true
pa=$(sed -n 's/^ *- hostPort: //p' "$ctl/kwok/clusters/control-a-$$/kwok.yaml" | head -1)
pb=$(sed -n 's/^ *- hostPort: //p' "$ctl/kwok/clusters/control-b-$$/kwok.yaml" | head -1)
[ -n "$pa" ] && [ -n "$pb" ] || { cat "$ctl/a.log" "$ctl/b.log"; fail 'a control create wrote no host port'; }
if [ "$pa" = "$pb" ]; then echo "collided: both clusters were given host port $pa"
else echo "no collision this time: ports $pa and $pb"; fi
# Give both apiservers up to 60s, then show how each container fares.
i=0; while [ "$i" -lt 120 ]; do
  up=0; for x in a b; do KUBECONFIG=$ctl/kubeconfig-$x kubectl get --raw /readyz > /dev/null 2>&1 && up=$((up + 1)); done
  restarts=$(docker inspect -f '{{.RestartCount}}' "kwok-control-a-$$-kube-apiserver" "kwok-control-b-$$-kube-apiserver" 2> /dev/null | awk '{s += $1} END {print s + 0}')
  [ "$up" -lt 2 ] && [ "$restarts" -eq 0 ] || break
  i=$((i + 1)); sleep 0.5
done
for x in a b; do
  KUBECONFIG=$ctl/kubeconfig-$x kubectl get --raw /readyz > /dev/null 2>&1 && r=ready || r='not ready'
  printf 'control-%s apiserver: %s, %s\n' "$x" "$r" "$(docker inspect -f '{{.State.Status}}, restarts {{.RestartCount}}' "kwok-control-$x-$$-kube-apiserver" 2> /dev/null || echo 'no container')"
done
for x in a b; do
  KWOK_WORKDIR=$ctl/kwok kwokctl delete cluster --name "control-$x-$$" --kubeconfig "$ctl/kubeconfig-$x" > /dev/null 2>&1 || true
done
[ "$(docker ps -a -q --filter "name=control-.-$$" | wc -l | tr -d ' ')" -eq 0 ] || fail 'control clusters left containers'

after=$(outside)
echo; echo '== outside the worktrees, after'; printf '%s\n' "$after"
[ "$before" = "$after" ] || fail 'a file outside the worktrees changed'
echo 'ok   nothing outside the worktrees changed'
