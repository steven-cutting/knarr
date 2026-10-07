#!/bin/sh
# Ticket 10 evidence: install the tools every other script here uses, into one
# work dir. The conda tools (kind, kubectl, helm, shellcheck) come from 0003's
# `cluster` environment: 01's pixi.toml.proposed is copied, locked and
# installed with --locked. kwok, kwokctl, k3d and setup-envtest are downloaded
# for the host platform and kept only if their sha256 is in the pin lines
# below, which are copied from evidence/01/tools.txt, never re-pinned.
# Usage: sh fetch.sh <empty-work-dir> > fetch.txt 2>&1
# Afterwards: PATH=<dir>/bin:<dir>/.pixi/envs/cluster/bin:$PATH
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=${1:?usage: fetch.sh <empty-work-dir>}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
quiet() { log=$1; shift; "$@" > "$log" 2>&1 || { cat "$log"; fail "$*"; }; }
# verify <file> <sha256>: true only if the file hashes to the pin.
verify() { [ "$(sha "$1")" = "$2" ]; }
case $(uname -sm) in
  'Darwin arm64') platform=osx-arm64;;
  'Linux x86_64') platform=linux-64;;
  *) fail "no pins for $(uname -sm)";;
esac
printf 'date: %s\nhost: %s (%s)\n%s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(uname -sm)" "$platform" "$(pixi --version)"

echo; echo '== pixi: the cluster environment from 01/pixi.toml.proposed'
cd "$work"
cp "$here/../01/pixi.toml.proposed" pixi.toml
# 01 commits no pixi.lock (03 does), so lock here first. The sha256 shows a
# re-solve: it changes when conda-forge moves a transitive dependency.
quiet lock.log pixi lock
echo "pixi.lock sha256 $(sha pixi.lock)"
quiet install.log pixi install --locked -e cluster
tail -1 install.log
env=$work/.pixi/envs/cluster
for t in kind kubectl helm shellcheck; do [ -x "$env/bin/$t" ] || fail "no $t in the cluster env"; done
printf 'kind:       %s\n' "$("$env/bin/kind" version)"
printf 'kubectl:    %s\n' "$("$env/bin/kubectl" version --client 2>&1 | head -1)"
printf 'helm:       %s\n' "$("$env/bin/helm" version --short)"
printf 'shellcheck: %s\n' "$("$env/bin/shellcheck" --version | sed -n 's/^version: //p')"
printf 'cluster env size: %s\n' "$(du -sh "$env" | cut -f1)"

echo; echo '== .tools-style downloads (pin lines copied from evidence/01/tools.txt)'
# name version platform url sha256 member
pins='
kwok 0.8.0 linux-64 https://github.com/kubernetes-sigs/kwok/releases/download/v0.8.0/kwok-linux-amd64 f5a4385a2ae1b9dd7f8acae18e002a75c0ebba124ae9d7259aa8dadb50711f46 -
kwok 0.8.0 osx-arm64 https://github.com/kubernetes-sigs/kwok/releases/download/v0.8.0/kwok-darwin-arm64 69a064ec98d37844d9d742b5b28ff57825659a983ccc3e208daa6948b94d64ba -
kwokctl 0.8.0 linux-64 https://github.com/kubernetes-sigs/kwok/releases/download/v0.8.0/kwokctl-linux-amd64 d5743166c657283d6e827c7c4c20cacfd9009fd94830f06718ca7b2c7099461f -
kwokctl 0.8.0 osx-arm64 https://github.com/kubernetes-sigs/kwok/releases/download/v0.8.0/kwokctl-darwin-arm64 9323a59adb9c27854bd2a76652ad00258bcbb68acc40aba0dc21e362b67b7d6a -
k3d 5.9.0 linux-64 https://github.com/k3d-io/k3d/releases/download/v5.9.0/k3d-linux-amd64 06d8f25bc3a971c4eb29e0ff08429b180402db0f4dec838c9eac427e296800a0 -
k3d 5.9.0 osx-arm64 https://github.com/k3d-io/k3d/releases/download/v5.9.0/k3d-darwin-arm64 fe106541d5d0a3f18debcd4d432a16f8c0ce3e6ddc06f8fbb6f696a122313e00 -
setup-envtest 0.25.2 linux-64 https://github.com/kubernetes-sigs/controller-runtime/releases/download/v0.25.2/setup-envtest-linux-amd64 94534f83896f3b09934d9570b213fbda04aa5c17457942270928cdca0317bf9b -
setup-envtest 0.25.2 osx-arm64 https://github.com/kubernetes-sigs/controller-runtime/releases/download/v0.25.2/setup-envtest-darwin-arm64 7c95d67911e157d2caa02f599bcf9321b4e759d2f008749b4d03ed9d3e6a8c69 -
'
mkdir -p "$work/bin" "$work/dl"
printf '%s\n' "$pins" > "$work/pins.in"
n=0
while read -r name version plat url want member; do
  [ "$plat" = "$platform" ] || continue
  f=$work/dl/$name
  curl -fsSL --proto '=https' -o "$f" "$url"
  verify "$f" "$want" || fail "$name $version: sha256 $(sha "$f"), pin $want"

  [ "$member" = - ] || fail "$name: archive members are not handled here"
  mv "$f" "$work/bin/$name"; chmod +x "$work/bin/$name"
  printf 'ok   %-14s %-7s %s\n     sha256 %s (matches pin)\n' "$name" "$version" "${url##*/}" "$want"
  n=$((n + 1))
done < "$work/pins.in"
[ "$n" -eq 4 ] || fail "expected 4 pinned tools for $platform, installed $n"
b=$work/bin
printf 'kwok:          %s\n' "$("$b/kwok" --version)"
printf 'kwokctl:       %s\n' "$("$b/kwokctl" --version)"
printf 'k3d:           %s\n' "$("$b/k3d" version | tr '\n' ' ')"
printf 'setup-envtest: %s\n' "$("$b/setup-envtest" --help 2>&1 | head -1 | sed 's|^Usage: [^ ]*/|Usage: |')"

echo; echo "== a tampered download is refused by the same check"
cp "$work/bin/kwok" "$work/dl/kwok-tampered"; printf x >> "$work/dl/kwok-tampered"
kwok_pin=$(awk -v p="$platform" '$1=="kwok" && $3==p {print $5}' "$work/pins.in")
if verify "$work/dl/kwok-tampered" "$kwok_pin"; then fail "tampered kwok accepted"; fi
echo "kwok with one byte appended: refused (sha256 $(sha "$work/dl/kwok-tampered"))"

echo; echo '== envtest assets: etcd and kube-apiserver 1.35 from setup-envtest'
# The archives come from setup-envtest's release index (controller-tools
# releases), which lists a sha512 per archive; setup-envtest itself is pinned
# above. It leaves the asset directory read-only: chmod -R u+w to remove it.
"$work/bin/setup-envtest" list --bin-dir "$work/envtest" 2>&1 | grep -E 'v1\.3[5-7]\.' | grep "$(uname -s | tr '[:upper:]' '[:lower:]')" | head -4
envtest=$("$work/bin/setup-envtest" use 1.35.0 --bin-dir "$work/envtest" -p path)
printf 'installed: %s\n' "${envtest#"$work"/}"
printf 'kube-apiserver: %s\netcd: %s\n' "$("$envtest/kube-apiserver" --version)" "$("$envtest/etcd" --version | head -1)"
