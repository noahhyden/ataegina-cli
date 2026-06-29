# Changelog

All notable changes to ataegina are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries are reconstructed from the git history and the commit messages of each
release. Versions 0.3.1 and 0.3.2 were cut as commits that bump the `VERSION=`
line but were not separately git-tagged.

## [Unreleased]

_Nothing yet._

## [0.5.0] - 2026-06-26

### Fixed

- `ataegina init` no longer aborts under `set -e` during stack detection. Two
  cases, both surfaced by dogfooding across real repos: a `package.json` with no
  `dev` script made `pkg_dev_script`'s pipeline fail under `pipefail` (silent
  exit 1, no output), and `emit_config` could return non-zero on a falsy trailing
  test (a detected backend with no `BACKEND_ENV`), so `init` printed the full
  config yet exited 1. Both are covered by `tests/init.bats`.

### Removed

- The agent-fleet dispatcher (`ataegina run` / `ataegina status`) and everything
  that supported it: the supervisor and its crash-recovery state file, the
  draft-PR-on-success step, and the `ATE_AGENT_CMD`, `ATE_TASKS_DIR`,
  `ATE_WORKTREES_DIR`, `ATE_MAX_AGENTS`, `ATE_STALL_WARN_SEC`,
  `ATE_STALL_KILL_SEC`, and `ATE_MAX_ATTEMPTS` config keys. ataegina is now
  purely the worktree-aware dev launcher: collision-free ports, processes, and
  per-worktree databases. Orchestrating which agent runs where is left to
  whatever tool you already use; ataegina just gives each worktree a clean,
  isolated stack to run in. (`ATE_BASE_BRANCH` stays, now solely as the
  scope-detection base ref.)

### Changed

- A bare `ataegina` with no subcommand now prints usage and exits instead of
  silently running `up` (which started dev servers as a side effect).
- Moved the internal design spikes (`portability`, `smart-ports`,
  `onboarding-redesign`) under `docs/design/` and marked them as historical
  design notes whose embedded line numbers and counts have since drifted.

### Added

- bats-core test suite under `tests/` covering index assignment and recycling,
  port derivation, the per-repo registry, scope detection, `config`
  get/set/unset/list, `down` pidfile teardown, per-worktree database
  deconfliction, and the version comparator. Driven entirely by a temp registry
  and `ATE_PORT_TOOL=none`, so it needs no servers, databases, or network, and
  runs on both macOS (system bash 3.2) and Linux.
- GitHub Actions CI: shellcheck on `ataegina` (bash) and `install.sh` (sh); the
  bats suite on an `ubuntu-latest` + `macos-latest` matrix; a job asserting the
  macOS run exercises system bash 3.2; and a release-verify job that checks
  `ataegina.sha256` against the committed script and the `VERSION=` line against
  the release tag.
- Release-hygiene docs: this changelog, `SECURITY.md`, `CODE_OF_CONDUCT.md`, and
  GitHub issue / pull-request templates.

## [0.4.0] - 2026-06-22

### Added

- Per-worktree database deconfliction (off unless `DB_NAME` is set). Each
  worktree N>0 gets its own database `DB_NAME$DB_SUFFIX$N`; the primary (index 0)
  keeps the unsuffixed `DB_NAME` (the shared dev DB). New `ataegina db
  [name|url|create|drop]` command, `DB_KIND` defaults (postgres / mysql / sqlite
  / custom), `DB_URL_TEMPLATE` injection into `DB_URL_VAR` (default
  `DATABASE_URL`), optional `DB_AUTO_CREATE` on `up`, overridable
  `DB_CREATE_CMD` / `DB_DROP_CMD`, and `ate_db_create` / `ate_db_drop` hook
  escape hatches. `db drop` refuses to drop the primary's database; `down` never
  drops a database.

### Fixed

- Checksum format fix so the published `ataegina.sha256` matches what `ataegina
  update` and `install.sh` verify.

## [0.3.2] - 2026-06-22

### Added

- `ataegina logs [both|backend|frontend] [-n N] [--no-follow]` to follow this
  worktree's server logs in real time (the servers run detached, so the log
  files are the source of truth).
- Exported `FRONTEND_URL` into the hook environment alongside `BACKEND_URL`, so a
  backend building CORS / OAuth-redirect / email URLs can address this tree's
  frontend.

## [0.3.1] - 2026-06-22

### Added

- Readiness poll on `up`: after launching a server, briefly poll its port and
  report `ready` or `still starting` instead of fire-and-forget.
- Pid-tracked `down`: `up` records the launched pid in a per-side pidfile, so
  `down` can stop a process that has not yet bound its port (dependency sync /
  first compile) and clean up orphans.

### Fixed

- Dropped a backend-directory leak between invocations.

## [0.3.0] - 2026-06-22

### Fixed

- Registry is now per-repo by default: each primary checkout gets its own
  tab-separated index file under `REGISTRY_DIR/repos/<key>`, so two unrelated
  checkouts never share one index space (which would make both primaries index 0
  and collide on ports). Set `ATE_REGISTRY` to force one shared file.
- Scope base resolution is upstream-aware: scope detection diffs against the
  current branch's upstream, else the remote default branch (`origin/HEAD`), else
  the first local of main/master/develop, instead of assuming a fixed trunk.
- `doctor` resolves the launcher on PATH under the invoked name (e.g. the `ate`
  alias), no longer false-warning when run via the alias.
- Auto-detected empty-diff scope of `none` is nudged to `both` on `up` (an
  explicit `--scope none` / `scope: none` still means none).

## [0.2.0] - 2026-06-22

### Added

- Scope-aware `up`: classify the worktree's git diff into a scope (frontend /
  backend / both / none) and start only the surfaces a task touches, pointing the
  rest at the shared default servers in the primary checkout. Override per run
  with `--scope`, per task with a `scope:` field, or disable with
  `ATE_SCOPE_AUTO=0`.
- Dispatcher: `ataegina run` and `ataegina status`. A crash-recoverable
  supervisor that fans a queue of task specs out to a fleet of agents, each in its
  own fresh worktree, respawns on crash or stall, and opens a draft pull request
  on success. It never merges and never removes a worktree.
- Portable port detection: a port-tool layer that auto-detects lsof, then ss
  (iproute2), then fuser, then parsing `/proc/net/tcp` (Linux), else none.
  Overridable with `ATE_PORT_TOOL`.
- `ataegina config get/set/list/unset/path`: read and write whitelisted scalar
  keys in `ataegina.config.sh` from the CLI. Values are stored single-quoted so a
  `$VAR` stays literal; non-whitelisted keys and hook-function names are refused.
- `ataegina update` plus an opt-in, throttled (<=1/24h) update-check notice
  (`ATE_UPDATE_CHECK=1`). `update` self-replaces the script with the latest
  published release, verifying a published SHA-256 and bash-parse-checking the
  download before installing.
- `install.sh`: a POSIX-sh `curl | sh` installer that resolves the latest release,
  downloads it, verifies the checksum, parse-checks it, and installs to
  `~/.local/bin` with no sudo. Install / platform documentation.

## [0.1.0] - 2026-06-22

### Added

- Initial release: a zero-dependency, bash-3.2-compatible harness that gives each
  git worktree a stable integer index N (persisted in a machine-local registry)
  and derives non-colliding ports from it (`FRONT_PORT_BASE + N` /
  `BACK_PORT_BASE + N`), with per-worktree log dirs. Commands: `up`, `down`,
  `ports`, `list`, `prune`.
- `ataegina init` with stack auto-detection (Next / CRA / Vite frontends; uv /
  Django / Rails / Node / Go backends) that writes a declarative
  `ataegina.config.sh`, plus the declarative hook model (`FRONTEND_*` /
  `BACKEND_*` consumed by default `ate_start_*` hooks).
- `ataegina doctor`: read-only diagnostics for the current tree (launcher on
  PATH, registry, config, runnable surfaces, port availability, URLs) usable as a
  CI gate.

[0.5.0]: https://github.com/noahhyden/ataegina-cli/releases/tag/v0.5.0
