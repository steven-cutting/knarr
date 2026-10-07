#!/bin/sh
# Ticket 10 evidence: resolve every image the local cluster tiers pull to a
# registry digest, and require each to publish linux/amd64 (CI) and
# linux/arm64 (this Mac). The kind node digest must equal the one the kind
# v0.33.0 release notes publish; the CA digest must equal 0003's.
# Kubernetes minor 1.35 is 0003's choice (kind, kwok, CA and the conda kubectl
# 1.34.3 all support it); the patch per tool is the newest that tool ships.
# Needs docker (buildx imagetools) and gh.
# Usage: sh pins.sh <tools-dir> > pins.txt 2>&1   (k3d from fetch.sh's dir)
set -eu
tools=$(cd "${1:?usage: pins.sh <tools-dir>}" && pwd)
PATH=$tools/bin:$PATH; export PATH
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
printf 'date: %s\n%s\n\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(docker version --format 'docker {{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}')"
digest() { docker buildx imagetools inspect "$1" --format '{{json .Manifest.Digest}}' | tr -d '"'; }
platforms() { docker buildx imagetools inspect "$1" | awk '$1=="Platform:"{print $2}' | sort -u | tr '\n' ' '; }
pin() { # image [expected-digest]
  d=$(digest "$1")
  case $d in sha256:*) ;; *) fail "$1: no digest";; esac
  [ -z "${2:-}" ] || [ "$d" = "$2" ] || fail "$1: registry says $d, expected $2"
  p=$(platforms "$1")
  case " $p" in *' linux/amd64 '*) ;; *) fail "$1: no linux/amd64 ($p)";; esac
  case " $p" in *' linux/arm64 '*) ;; *) fail "$1: no linux/arm64 ($p)";; esac
  printf '%s@%s\n    platforms: %s\n' "$1" "$d" "$p"
}

echo '== kind v0.33.0: node images its release notes publish (1.34 to 1.37)'
notes=$(gh release view v0.33.0 -R kubernetes-sigs/kind --json body --jq .body | tr -d '\r')
printf '%s\n' "$notes" | grep -E '^\* v1\.3[4-7]\.' || fail 'no node image list in the release notes'
# shellcheck disable=SC2016  # the backticks are literal Markdown
kind_node=$(printf '%s\n' "$notes" | sed -n 's/^\* v1\.35\.[0-9]*: `\(kindest\/node:v1\.35\.[0-9]*\)@\(sha256:[0-9a-f]*\)`$/\1 \2/p')
[ -n "$kind_node" ] || fail 'no 1.35 node image in the kind v0.33.0 notes'
echo; echo '== kind node image (cluster minor 1.35): release-note digest equals the registry'
# shellcheck disable=SC2086  # "<image> <digest>" splits into pin's two arguments
pin $kind_node

echo; echo '== kwok v0.8.0: the all-in-one cluster image for 1.35, and the images'
echo '   kwokctl --runtime docker pulls with KWOK_KUBE_VERSION=v1.35.5'
pin registry.k8s.io/kwok/cluster:v0.8.0-k8s.v1.35.5
pin registry.k8s.io/kwok/kwok:v0.8.0
for c in kube-apiserver kube-controller-manager kube-scheduler; do pin "registry.k8s.io/$c:v1.35.5"; done
pin registry.k8s.io/etcd:3.6.10-0

echo; echo '== k3d v5.9.0: its default k3s image is 1.35'
k3s=$(k3d version 2>/dev/null | sed -n 's/^k3s version \(v[^ ]*\) (default)$/\1/p') || true
[ -n "$k3s" ] || fail 'k3d not on PATH or no default k3s version printed'
echo "k3d default k3s: $k3s"
case $k3s in v1.35.*) ;; *) fail "k3d default k3s $k3s is not 1.35";; esac
pin "rancher/k3s:$k3s"
pin ghcr.io/k3d-io/k3d-tools:5.9.0

echo; echo '== Cluster Autoscaler 1.35.2 (pinned in 0003; re-resolved, must be unchanged)'
pin registry.k8s.io/autoscaling/cluster-autoscaler:v1.35.2 sha256:aac369dc283927a623deb1af54696efcc722ae79255aa07788422e495bab887d

echo; echo '== pause 3.10: preloaded in the kind node image; the base of the stand-in image'
pin registry.k8s.io/pause:3.10
