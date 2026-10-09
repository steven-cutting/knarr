# Adversarial review

Requested through Claude Code 2.1.295 with `--model opus --effort medium`,
read-only tools, and no session persistence. The installed CLI documents `opus`
as the latest Opus alias; there was no environment or settings override for that
alias. The reviewer identified itself as **Claude Opus 5.5**, resolved model ID
`claude-opus-5-5`, also present in the CLI's model-usage metadata.

The reviewer read the implementation, tests, ticket, ADR, documentation contract,
and evidence. It did not execute commands. The implementation agent ran the
command tests and full gate separately; this record does not attribute those
runs to Claude.

## Findings addressed

- **High: case-sensitive filesystem failure.** The fixture copied `justfile`
  although Git tracks `Justfile`, and two fault-injection tests used the same
  wrong case. macOS accepted those references; Linux would fail before testing
  coverage. All references now use the tracked spelling. The native Linux
  follow-up remains open rather than treating this static fix as runtime proof.
- **Timeout risk, not a demonstrated failure.** The cold-compilation test used
  a 60-second command timeout. It now uses 120 seconds, matching the existing
  cold-lint test and allowing slower CI machines the same headroom.
- **Testing introduction.** It no longer says everything on the page runs in
  the gate; it distinguishes the unit suite from the optional coverage command.
- **Decision navigation.** Added the pre-existing missing 0010 entry before 0011.
- **Scratch location.** Added a fixture comment identifying AGENTS.md's
  `ai_tmp/` requirement. Disposable directories are removed on normal completion.

## Placement retained

The reviewer suggested moving the developer command out of `scripts/checks/`,
or explaining its placement. It remains beside its command-boundary tests and
the existing developer adapters `cluster.py`, `image.py`, and `deployment.py`.
That directory already contains commands outside the offline gate; location
does not enroll a recipe in `just check`. No gate recipe or threshold was added.

## Findings the reviewer considered sound

Fresh-report enforcement, collection before gleeunit halts, test-failure status,
startup instrumentation, inventory validation, source-line bounds, preserved
EUnit options, separate FFI reporting, exclusions, and the documented generated
wrapper and subprocess limitations were all judged sound. No controller,
specification, dependency, pin, or documentation-registration defect was found.

The captured evidence is refreshed after the fixes so its hashes identify the
delivered command and tests. Final validation is recorded in
[ticket 26](../../issues/26-spike-coverage.md#hand-back-notes).
