#!/bin/sh
# Ticket 10 evidence: one local cluster per worktree, for each runner. Every
# other script here creates its clusters through this file, and its shape is
# the draft of 13's cluster-up, cluster-down and image-load recipes.
#
#   up     create the cluster name.sh derives from <worktree>, with its
#          kubeconfig (and kwokctl's workdir) under <worktree>/.cluster; no
#          host port is fixed. Returns once the apiserver is ready and, except
#          for envtest, a node is Ready and the default ServiceAccount exists.
#   down   delete it and its state dir.
#   load   make a local docker image available to the cluster's pods.
#
# Runners: kind, k3d, kwokctl (docker runtime), envtest (etcd and
# kube-apiserver from setup-envtest, started here: a shell stand-in for
# controller-runtime's envtest library, which needs Go).
# Images and versions: pins.txt. Tools: fetch.sh's work dir.
# Usage: sh cluster.sh <tools-dir> <runner> up|down|load <worktree-dir> [image]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
usage='usage: cluster.sh <tools-dir> <runner> up|down|load <worktree-dir> [image]'
tools=$(cd "${1:?$usage}" && pwd)
runner=${2:?$usage}; action=${3:?$usage}; wt=${4:?$usage}
PATH=$tools/bin:$tools/.pixi/envs/cluster/bin:$PATH; export PATH
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
n=$(sh "$here/name.sh" "$wt" name)
dir=$(sh "$here/name.sh" "$wt" dir)
kc=$(sh "$here/name.sh" "$wt" kubeconfig)
KWOK_WORKDIR=$(sh "$here/name.sh" "$wt" kwok-workdir); export KWOK_WORKDIR
KUBECONFIG=$kc; export KUBECONFIG

# Pinned in pins.txt (kind v0.33.0 release notes, kwok v0.8.0, k3d v5.9.0).
kind_node=kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0
k3s=rancher/k3s:v1.35.5-k3s1@sha256:2074403abe1bded11ef3dde09d457e13be8e0b64c218b1c4f8269b4565cfbc65
kwok_kube=v1.35.5
envtest_version=1.35.0

ready() { # wait for a schedulable cluster: a Ready node and the default SA
  # kubectl wait --all fails at once if no node exists yet, so wait for one first.
  i=0; until [ -n "$(kubectl get nodes -o name 2> /dev/null)" ]; do
    i=$((i + 1)); [ "$i" -lt 360 ] || fail "$n: no node registered"; sleep 0.5
  done
  kubectl wait --for=condition=Ready node --all --timeout=180s > /dev/null
  i=0; until kubectl get serviceaccount default > /dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -lt 120 ] || fail "$n: no default ServiceAccount"; sleep 0.5
  done
}
# freeports [count]: ports the OS reports free on 127.0.0.1, distinct because
# every socket stays open until all are chosen. The socket closes before the
# apiserver binds the port, so this narrows the race between worktrees (an
# ephemeral port is rarely handed out again within seconds) without closing
# it: a lost race fails "up", and rerunning picks new ports.
freeports() {
  perl -MIO::Socket::INET -e 'my @s = map { IO::Socket::INET->new(Listen => 1, LocalAddr => "127.0.0.1", LocalPort => 0) or die "$!\n" } 1 .. ($ARGV[0] || 1); print join(" ", map { $_->sockport } @s), "\n"' "${1:-1}"
}

envtest_up() {
  bins=$(setup-envtest use "$envtest_version" --bin-dir "$tools/envtest" -i -p path)
  e=$dir/envtest; mkdir -p "$e/certs"
  openssl genrsa -out "$e/sa.key" 2048 2> /dev/null
  openssl rsa -in "$e/sa.key" -pubout -out "$e/sa.pub" 2> /dev/null
  token=$(openssl rand -hex 16)
  printf '%s,admin,admin,system:masters\n' "$token" > "$e/tokens.csv"
  # SC2218: false positive in 0.11.0, freeports is defined above. SC2046: the
  # split into three ports is the point.
  # shellcheck disable=SC2218,SC2046
  set -- $(freeports 3); cport=$1; pport=$2; aport=$3
  "$bins/etcd" --data-dir "$e/etcd" --name envtest \
    --listen-client-urls "http://127.0.0.1:$cport" --advertise-client-urls "http://127.0.0.1:$cport" \
    --listen-peer-urls "http://127.0.0.1:$pport" --initial-advertise-peer-urls "http://127.0.0.1:$pport" \
    --initial-cluster "envtest=http://127.0.0.1:$pport" > "$e/etcd.log" 2>&1 &
  echo $! > "$e/etcd.pid"
  "$bins/kube-apiserver" --etcd-servers "http://127.0.0.1:$cport" \
    --bind-address 127.0.0.1 --advertise-address 127.0.0.1 --secure-port "$aport" --cert-dir "$e/certs" \
    --service-cluster-ip-range 10.0.0.0/24 --token-auth-file "$e/tokens.csv" --authorization-mode RBAC \
    --service-account-issuer https://kubernetes.default.svc --service-account-key-file "$e/sa.pub" \
    --service-account-signing-key-file "$e/sa.key" > "$e/apiserver.log" 2>&1 &
  echo $! > "$e/apiserver.pid"
  kubectl config set-cluster "$n" --server "https://127.0.0.1:$aport" --insecure-skip-tls-verify=true > /dev/null
  kubectl config set-credentials "$n" --token "$token" > /dev/null
  kubectl config set-context "$n" --cluster "$n" --user "$n" > /dev/null
  kubectl config use-context "$n" > /dev/null
  i=0; until kubectl get --raw /readyz > /dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -lt 240 ] || { tail -5 "$e/apiserver.log" >&2; fail "$n: apiserver not ready"; }; sleep 0.25
  done
}
envtest_down() {
  for p in apiserver etcd; do
    f=$dir/envtest/$p.pid
    [ -f "$f" ] || continue
    pid=$(cat "$f"); kill "$pid" 2> /dev/null || true
    i=0; while kill -0 "$pid" 2> /dev/null; do i=$((i + 1)); [ "$i" -lt 100 ] || { kill -9 "$pid" 2> /dev/null || true; break; }; sleep 0.1; done
  done
}

case $runner:$action in
  kind:up)
    mkdir -p "$dir"
    kind create cluster --name "$n" --image "$kind_node" --kubeconfig "$kc" --wait 180s > "$dir/up.log" 2>&1 || { cat "$dir/up.log" >&2; fail "kind create $n"; }
    ready;;
  kind:down) kind delete cluster --name "$n" --kubeconfig "$kc" > /dev/null 2>&1; rm -rf "${dir:?}";;
  kind:load) kind load docker-image "${5:?$usage}" --name "$n" > /dev/null 2>&1;;

  k3d:up)
    mkdir -p "$dir"
    # Port 0: docker picks a free 127.0.0.1 port. k3d then writes ":0" into its
    # kubeconfig, so the server URL is rewritten from the published port.
    k3d cluster create "$n" --image "$k3s" --api-port 127.0.0.1:0 --no-lb \
      --k3s-arg '--disable=traefik@server:*' --kubeconfig-update-default=false \
      --kubeconfig-switch-context=false --wait --timeout 180s > "$dir/up.log" 2>&1 || { cat "$dir/up.log" >&2; fail "k3d create $n"; }
    k3d kubeconfig get "$n" > "$kc"
    port=$(docker port "k3d-$n-server-0" 6443/tcp | head -1)
    kubectl config set-cluster "k3d-$n" --server "https://$port" > /dev/null
    ready;;
  k3d:down) k3d cluster delete "$n" > /dev/null 2>&1; rm -rf "${dir:?}";;
  k3d:load) k3d image import "${5:?$usage}" -c "$n" > /dev/null 2>&1;;

  kwokctl:up)
    mkdir -p "$dir"
    # kwokctl's default port is the first free one counting down from 32766,
    # so two clusters created at once both take it; pass a free port instead.
    KWOK_KUBE_VERSION=$kwok_kube kwokctl create cluster --name "$n" --runtime docker --kubeconfig "$kc" \
      --kube-apiserver-port "$(freeports)" \
      --wait 180s > "$dir/up.log" 2>&1 || { cat "$dir/up.log" >&2; fail "kwokctl create $n"; }
    kwokctl scale node --name "$n" --replicas 1 > /dev/null 2>&1
    ready;;
  kwokctl:down) kwokctl delete cluster --name "$n" --kubeconfig "$kc" > /dev/null 2>&1; rm -rf "${dir:?}";;
  kwokctl:load) echo 'n/a: kwok pods do not run, so no image is pulled';;

  envtest:up) mkdir -p "$dir"; envtest_up;;
  envtest:down) envtest_down; rm -rf "${dir:?}";;
  envtest:load) echo 'n/a: envtest has no kubelet';;
  *) fail "$usage";;
esac
