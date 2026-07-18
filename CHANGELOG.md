# Changelog

All notable changes to ataegina are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries are reconstructed from the git history and the commit messages of each
release. Versions 0.3.1 and 0.3.2 were cut as commits that bump the `VERSION=`
line but were not separately git-tagged.

## [Unreleased]

## [0.6.0] - 2026-07-18

### Fixed

- **`down` no longer leaks worker/child processes (the "processes pile up"
  drain).** Teardown killed only the recorded launch pid and, when a port tool
  was present, the single port holder — so a dev server's worker/helper children
  (uvicorn `--reload`, vite/esbuild, webpack/turbopack workers, a supervisor
  above the port holder) were orphaned and kept their memory, leaking one per
  up/down cycle; on hosts without lsof/ss/fuser *nothing but the wrapper* was
  killed. `down` now enumerates the full process tree under each root from a
  single portable `ps` snapshot before killing, `SIGTERM`s it, then `SIGKILL`s
  survivors, independent of any port tool. Covered by `tests/teardown_orphans.bats`.
- **Concurrent first-`up` no longer races two worktrees onto the same index.**
  `resolve_index` scanned then appended the registry with no lock, so parallel
  worktrees could take the same index → identical ports *and* the same
  per-worktree database. Now serialized with an atomic `mkdir` lock (portable;
  `flock` is Linux-only) plus a double-checked re-read. `tests/concurrency.bats`.
- **A repo path containing a space no longer costs the primary its index 0.**
  `PRIMARY` was parsed with `awk '{print $2}'`, truncating a spaced path at the
  first space, so the primary checkout was misidentified and assigned a nonzero
  index (nonzero ports, and — with a DB configured — a suffixed DB instead of the
  shared one). Parsed with `sed` now. `tests/spaces_in_path.bats`.
- **Linked worktrees inherit the primary checkout's config.** The (naturally
  `.gitignore`d) config is not copied into a `git worktree add` tree, so a fresh
  worktree had none and `up`/`db` failed with "no backend/database configured".
  `load_config` now falls back to `<primary>/ataegina.config.sh` (the worktree's
  own config still wins). `tests/config_inheritance.bats`.
- **`up` exits 0 on a successful start with no frontend** (scope `backend`/`none`).
  A falsy trailing test made `cmd_up` return 1 under `set -e`, aborting `up` with
  exit 1 despite success (broke `ate up backend && …` and CI). `tests/up_exit_code.bats`.
- **`up` distinguishes a dead server from a slow one.** The readiness report said
  "still starting (first run can be slow)" even when the launched process had
  already died (bad command, missing dependency, crash); it now reports
  "FAILED to start — see &lt;log&gt;" for a dead pid. `tests/up_diagnostics.bats`.
- **`move`/`up` refuse an index whose derived port exceeds 65535** instead of
  assigning a slot whose servers can never bind. `tests/port_bounds.bats`.
- **`down` won't kill a recycled pid.** `up` records the launched pid's start-time;
  `down` skips a recorded pid whose start-time no longer matches (the id was reused
  for an unrelated process). `tests/pid_reuse.bats`.
- **`move` frees the old slot's servers itself.** It told you to run `down` to free
  the old ports, but `down` resolves the *new* index after the move and never reached
  them — orphaning the old servers on the old ports. `move` now stops the old slot
  before rewriting the registry (old index/ports/log dir are still in scope). Covered
  by `tests/move_real.bats`.
- `ataegina down` is no longer silent on success: each side now reports
  `<label>: stopped on :<port>` when it actually stops something, instead of
  printing nothing (only the "nothing to stop" path spoke before). Covered by
  `tests/down.bats`.

### Testing

- The suite grew from 44 to 98 tests, adding the first coverage that starts real
  processes and runs concurrently — real `up`/`down` lifecycle (python and node
  backends), a full two-worktree end-to-end (distinct ports + own databases,
  simultaneously), real frontend-scope borrow of the shared backend, real `logs`,
  and docker-gated integration against live **postgres** and **mysql** engines
  (per-worktree create/drop/isolation) that skip cleanly where docker is absent.

### Added

- `ataegina move N` relocates the current worktree to index `N` (and therefore
  a new derived port pair), rewriting the per-repo registry. It refuses an index
  already held by another live worktree, rejects index 0 (reserved for the
  primary) and non-numeric targets, frees the old index for reuse, and warns if
  either new port is already in use. Motivated by dogfooding: when a worktree's
  auto-assigned slot has a port permanently held by a process ataegina doesn't
  manage, the derived port can never bind, and the only previous fix was to
  hand-edit the registry. Covered by `tests/move.bats`.

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

[0.6.0]: https://github.com/noahhyden/ataegina-cli/releases/tag/v0.6.0
[0.5.0]: https://github.com/noahhyden/ataegina-cli/releases/tag/v0.5.0
