#!/bin/sh
# Ticket 10 evidence: how long a per-worktree cluster takes, for each runner.
#   up     cluster.sh up: create until the apiserver is ready and (except
#          envtest) a node is Ready and the default ServiceAccount exists
#   load   cluster.sh load of a ~256 MB stand-in image (pause 3.10 plus a
#          random 256 MiB layer, about the size of 0003's runtime env), then a
#          pod with imagePullPolicy: Never must run it, proving the load
#   down   cluster.sh down
# Three runs per runner, one after another, on a warm image cache (every
# pinned image is pulled first); the median is reported. OrbStack is timed in
# orbstack.sh, since it has one cluster per machine. Timings are from the host
# in README.md; CI runners will differ.
# Usage: sh timing.sh <tools-dir> <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
usage='usage: timing.sh <tools-dir> <empty-work-dir>'
tools=$(cd "${1:?$usage}" && pwd); work=${2:?$usage}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
PATH=$tools/bin:$tools/.pixi/envs/cluster/bin:$PATH; export PATH
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
now() { perl -MTime::HiRes=time -e 'printf "%.1f\n", time'; }
since() { perl -e 'printf "%.1f\n", $ARGV[1] - $ARGV[0]' "$1" "$(now)"; }
median() { printf '%s\n' "$@" | sort -n | sed -n "$(( ($# + 1) / 2 ))p"; }  # the middle of an odd count
runs=3
standin=knarr-standin:timing-$$
current=
cleanup() {
  [ -z "$current" ] || sh "$here/cluster.sh" "$tools" "${current%% *}" down "${current#* }" > /dev/null 2>&1 || true
  docker rmi -f "$standin" > /dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'date: %s\nhost: %s, %s, %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(sysctl -n machdep.cpu.brand_string 2> /dev/null || uname -m)" \
  "$(uname -sm)" "$(docker version --format 'docker {{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}')"

echo; echo '== warm the image cache (pull time is not measured)'
for img in \
  kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0 \
  rancher/k3s:v1.35.5-k3s1@sha256:2074403abe1bded11ef3dde09d457e13be8e0b64c218b1c4f8269b4565cfbc65 \
  ghcr.io/k3d-io/k3d-tools:5.9.0@sha256:c57abce697e66feeb826922718738fe186b47779312d49d4e51e6fb9b8a6f34d \
  registry.k8s.io/kube-apiserver:v1.35.5 registry.k8s.io/kube-controller-manager:v1.35.5 \
  registry.k8s.io/kube-scheduler:v1.35.5 registry.k8s.io/etcd:3.6.10-0 registry.k8s.io/kwok/kwok:v0.8.0 \
  registry.k8s.io/pause:3.10@sha256:ee6521f290b2168b6e0935a181d4cff9be1ac3f505666ef0e3c98fae8199917a; do
  docker pull -q "$img" > /dev/null || fail "pull $img"
done
echo 'pulled'

echo; echo '== the stand-in image'
mkdir -p "$work/standin"
head -c 268435456 /dev/urandom > "$work/standin/blob"
cat > "$work/standin/Dockerfile" <<'EOF'
FROM registry.k8s.io/pause:3.10@sha256:ee6521f290b2168b6e0935a181d4cff9be1ac3f505666ef0e3c98fae8199917a
COPY blob /blob
EOF
docker build -q -t "$standin" "$work/standin" > /dev/null
rm "$work/standin/blob"
printf '%s: %s bytes\n' "$standin" "$(docker image inspect "$standin" --format '{{.Size}}')"

proves_load() { # the pod runs from the loaded image only; Never forbids a pull
  # 180s: a new k3s node pulls its sandbox image (rancher/mirrored-pause) from
  # Docker Hub before the first pod starts; kind preloads it.
  KUBECONFIG=$(sh "$here/name.sh" "$1" kubeconfig) kubectl run standin --image "$standin" \
    --image-pull-policy Never --restart Never > /dev/null
  KUBECONFIG=$(sh "$here/name.sh" "$1" kubeconfig) kubectl wait --for=condition=Ready pod/standin --timeout 180s > /dev/null
}

summary=$work/summary
printf '%-8s %-22s %-7s %-22s %-7s %-22s %s\n' runner 'up (s)' median 'load (s)' median 'down (s)' median > "$summary"
for runner in kind k3d kwokctl envtest; do
  echo; echo "== $runner"
  ups=; loads=; downs=
  r=1; while [ "$r" -le "$runs" ]; do
    wt=$work/$runner-$r; mkdir -p "$wt"
    current="$runner $wt"
    t=$(now); sh "$here/cluster.sh" "$tools" "$runner" up "$wt"; up=$(since "$t")
    # shellcheck disable=SC2218  # false positive in 0.11.0: proves_load is defined above
    case $runner in
      kind|k3d) t=$(now); sh "$here/cluster.sh" "$tools" "$runner" load "$wt" "$standin"; load=$(since "$t"); proves_load "$wt";;
      *) load=n/a;;
    esac
    t=$(now); sh "$here/cluster.sh" "$tools" "$runner" down "$wt"; down=$(since "$t")
    current=
    [ "$(docker ps -a -q --filter "name=$(sh "$here/name.sh" "$wt" name)" | wc -l | tr -d ' ')" -eq 0 ] || fail "$runner run $r left containers"
    printf 'run %s: up %ss  load %s  down %ss\n' "$r" "$up" "$load" "$down"
    ups="$ups $up"; loads="$loads $load"; downs="$downs $down"
    r=$((r + 1))
  done
  # shellcheck disable=SC2086  # the lists split into one argument per run
  if [ "$load" = n/a ]; then lm='n/a'; else lm=$(median $loads); fi
  # shellcheck disable=SC2086
  printf '%-8s %-22s %-7s %-22s %-7s %-22s %s\n' "$runner" "${ups# }" "$(median $ups)" "${loads# }" "$lm" "${downs# }" "$(median $downs)" >> "$summary"
done

echo; echo "== summary (seconds; $runs runs each, median of $runs)"
cat "$summary"
echo 'load n/a: kwok pods never run, so nothing is pulled; envtest has no kubelet.'
