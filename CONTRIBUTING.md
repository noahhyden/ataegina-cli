# Contributing

Thanks for taking a look. ataegina is deliberately small: vanilla bash, no
build step, no dependencies beyond `git` and `awk` plus a port backend (`lsof`,
or the `ss`/`fuser`/`proc` fallback). Keep it that way.

## Ground rules

- **Zero dependencies.** No package manager, no runtime, no compiled step. If a
  change needs a dependency, it probably belongs in your config hooks, not here.
- **bash 3.2 compatible.** Target plain `bash` and stay 3.2-safe: no associative
  arrays, `mapfile`/`readarray`, `${var^^}`, process substitution, or
  here-strings, and no GNU-only tool flags (the script must run on the macOS
  system bash as-is). Run `shellcheck ataegina` before opening a PR.
- **`install.sh` stays POSIX `sh`.** It is a `curl | sh` target: keep it small,
  readable, and free of bashisms.
- **Keep the algorithm intact.** Stable index assignment, port derivation, the
  registry format, and `$PWD`-anchoring are the contract. Changing them breaks
  existing registries; propose it explicitly in an issue first.
- **Stay generic.** No project-, company-, or stack-specific assumptions in the
  core script. Project specifics live in `ataegina.config.sh`.

## Workflow

1. Open an issue describing the change before large PRs.
2. One logical change per PR. Small is good.
3. Update the README and `ataegina.config.example.sh` if you change the CLI,
   the config keys, or the exported hook environment.
4. Cutting a release? Follow [`RELEASE.md`](RELEASE.md) so the published
   `ataegina.sha256` matches the committed `ataegina` (clients verify it).

## Testing

The suite has three tiers. The default run is hermetic; the heavier tiers are
opt-in so day-to-day `bats tests/` stays fast and needs no servers or network.

**Unit (default).** `bats tests/` — hermetic: a temp registry and
`ATE_PORT_TOOL=none`, no servers, databases, or network. Runs on macOS system
bash 3.2 and on Linux; CI runs it on both. Always run this before sending a
change. Integration and docker tests below skip automatically here.

**Integration (real processes).** `ATE_TEST_INTEGRATION=1 bats tests/` — also
runs the tests that start REAL dev-server processes (python/node/go) and exercise
the full `up`/`down` lifecycle, port binding, env injection, the two-worktree
end-to-end, `move`, and `logs`. Still network-free. Needs `python3` (and `node` /
`go` for those cases) and a port tool (`lsof` or `ss`); individual tests skip if a
runtime is missing. CI runs this as the `integration` job.

**Docker (live DB engines).** `ATE_TEST_INTEGRATION=1 ATE_TEST_DOCKER=1 bats tests/`
— additionally runs the per-worktree database tests against live **postgres** and
**mysql** containers (create/drop/isolation, and `up` auto-create). Needs docker;
implies pulling images (network), so it is **local-only** — CI does not run it, to
keep CI network-free. Each docker test skips cleanly when docker is unavailable.

To run just one tier's new file, e.g.: `ATE_TEST_INTEGRATION=1 bats tests/flagship_e2e.bats`.

**Coverage.** `ataegina`'s line coverage is gated at **≥ 99%** in CI. Measure it
locally with `scripts/coverage.sh` (needs `gem install bashcov`). It runs bashcov
**per test file** and unions the hits — a single `bashcov -- bats tests/` under-counts
because bats spawns hundreds of bash processes whose concurrent SimpleCov writes race.
The handful of never-covered lines are non-executable (awk-program bodies inside
single-quoted strings, empty `case` arms) — not missing tests.

`shellcheck ataegina` should stay clean (see the exclusion list in
`.github/workflows/ci.yml`), and any change to `ataegina` must be followed by
regenerating its checksum so `release-verify` passes:
`shasum -a 256 ataegina > ataegina.sha256` (or `sha256sum`).
