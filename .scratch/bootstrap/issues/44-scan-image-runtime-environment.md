# 44: Scan the image's runtime environment

**Context:** [Decision 0014](../../../docs/decisions/0014-dependency-updates-and-audit.md) scans the knarr image with grype, through `just image-scan`, and that scan reads the image's OS (`deb`) packages only. grype runs syft to catalogue packages, and syft selects 34 package catalogers for an image source and 57 for a directory. `conda-meta-cataloger` runs only on a directory ([grype-probe.txt](../evidence/27/grype-probe.txt), part 3), and grype 0.120.1 has no flag or configuration setting that selects catalogers. The branch's `audit.yml` run shows the result on the real image: six `libssl3t64` rows, all `deb` ([ci-audit.txt](../evidence/27/ci-audit.txt)). So the runtime environment the image ships at `/opt/knarr/.pixi/envs/runtime` is scanned by no job: erlang, the conda-forge openssl the BEAM links, perl 5.32.1 and zlib.

The runtime environment locks 13 packages for linux-64. Ticket 27's probe scanned the 8 of them that have a conda record on the maintainer's host, and did not scan the other 5 (`_openmp_mutex`, `libgcc`, `libgomp`, `libstdcxx` and `libxcrypt`). As an image, those records give 0 conda matches. As a directory, they give 7 conda matches, and the 4 with a fix are all in conda-forge's perl 5.32.1, matched through NVD CPEs:

- CVE-2022-48522, Critical, fixed in 5.35.5;
- CVE-2023-31484 and CVE-2023-31486, High, fixed in 5.38.0;
- CVE-2023-47038, High.

erlang's conda-forge build pins that perl (its build string is `pl5321`), so perl cannot move on its own. [Decision 0003](../../../docs/decisions/0003-tool-manager.md) already contemplated pruning perl from the runtime image, and requires the TLS check to be rerun in the pruned image if it is.

**What to build:**

- `just image-scan`, or a sibling recipe in the `audit` group, also scans the runtime environment as a directory, with the same `--only-fixed --fail-on high`.
- The directory is the linux-64 environment the image ships. Either copy it out of the built image (`docker create`, then `docker cp` of `/opt/knarr/.pixi/envs/runtime` into `build/`), or install it from the lock (`pixi install --locked -e runtime`). The image builds only in CI, on amd64 ([Decision 0012](../../../docs/decisions/0012-release-and-packaging.md)), and a local install on osx-arm64 is that platform's environment, not the one the image ships.
- The recipe fails when `conda-meta-cataloger` catalogues no package. A directory scan of the wrong path, or of a copy without `conda-meta`, otherwise finds nothing and passes. `grype -vv` logs the count, as part 3 of [grype-probe.sh](../evidence/27/grype-probe.sh) reads it.
- `audit.yml` runs it, in the `image-scan` job or one beside it, and the job is not required. It runs even when the OS-package scan fails: the image scan is red on the base image's `libssl3t64` finding until Ubuntu republishes, and a step after a failed one is skipped. Use a job of its own, or `if: ${{ !cancelled() }}` on the step.
- perl is decided, one of:
  - **Pruned** from the runtime image. Then rerun the TLS check 0003 names (`tls_check.escript`) in the pruned image, because pruning breaks the lock's guarantee that what was tested is what ships. The scan then has to read the copy out of the image, since the lock still installs perl.
  - **Accepted** with a dated, documented grype ignore for each CVE, giving the reason and the date it is looked at again.
- The hand-back records what the first run shows.

**Non-goals:**

- The OS-package scan and the base image, which 0014 settles.
- The environments that do not ship (default, cluster and audit) and the `tools.txt` downloads.
- An advisory source for conda-forge: none exists, and 0014's "What would reopen this" covers one appearing.
- Making the job required.

**Blocked by:** 27

**From 27:** [Decision 0014](../../../docs/decisions/0014-dependency-updates-and-audit.md); the hand-back notes in [ticket 27](27-spike-dependency-updates-and-audit.md#hand-back-notes); [grype-probe.txt](../evidence/27/grype-probe.txt), part 3, and [ci-audit.txt](../evidence/27/ci-audit.txt).

**MVP critical path:** no. It is maintenance hygiene, and the MVP does not need it.

**Status:** ready-for-agent, once 27 merges

- [ ] A recipe in the `audit` group scans the linux-64 runtime environment as a directory with `--only-fixed --fail-on high`. It exits 0 when nothing qualifies and 2 on a finding, as `just image-scan` does, and fails when it catalogues no conda package.
- [ ] `audit.yml` runs it even when the OS-package scan fails, and the job is not required.
- [ ] perl is pruned from the runtime image, with `tls_check.escript` rerun in the pruned image, or accepted with a dated, documented grype ignore for each CVE. 0014 carries an "Amended by ticket 44" note saying which, and that the image's conda records are scanned.
- [ ] **Authorization required:** the network, for `pixi install`, grype's vulnerability database and any image pull.
- [ ] **Authorization required:** one `audit.yml` dispatch on the branch. The hand-back records the run, the matches with a fix and the job's verdict.
- [ ] `just check` ends with "All checks passed and the worktree is unchanged."
