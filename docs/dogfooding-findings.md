# Dogfooding findings — 2026-07-18

A hands-on dogfooding pass on a real workstation (Linux, bash 5.2; validated for
macOS system bash 3.2 via CI) that started from a user report of "memory issues"
and "a hard time getting ataegina working." It surfaced **9 bugs**, all fixed on
`fix/dogfooding-findings` (PR #16), each with a regression test proven to fail on
the pre-fix code.

## Method & isolation

An isolated harness drove **this repo's** `ataegina` against a throwaway full-stack
git repo whose "servers" are real python listeners — so `up`/`down` exercise the
real detached-process lifecycle, which the original unit suite never did (it forces
`ATE_PORT_TOOL=none` and starts nothing). The registry, logs, and ports were all
sandboxed, so the real `~/.config/ataegina` and `/tmp/ate-wt*` were never touched.
The harness is preserved in [`../sandbox/`](../sandbox/); the reproducible versions
of every scenario live in [`../tests/`](../tests/).

The through-line: **every one of these bugs lived where the old suite structurally
could not reach** — it forced `ATE_PORT_TOOL=none`, started no processes, and ran
serially. So the fix was as much about the test harness (real processes, concurrency,
real DB engines) as about the launcher.

## Root cause of the original report

- **Stale `ate` on `PATH`** (resolved by the user): `~/.local/bin/ate` pointed at a
  *different, older checkout* (v0.3.1), so the command line ran code missing all of
  v0.4/v0.5. This alone explained most of "hard to get working."
- **The "memory issues"** were bug #2 below — `down` orphaning worker processes.

## Bugs found and fixed

| # | Bug | Severity | Fix commit |
|---|-----|----------|-----------|
| 2 | `down` orphaned a dev server's worker/helper children (uvicorn `--reload`, vite/esbuild, webpack workers, a supervisor above the port holder). It killed only the recorded wrapper pid + the single port holder, so siblings leaked — one process per up/down cycle (measured ~40 MB/cycle); on hosts without lsof/ss/fuser it killed *nothing but the wrapper*. **The memory drain.** | Critical | `f98488e` |
| 4 | Concurrent first-`up` raced two worktrees onto the same index → identical ports **and** the same per-worktree DB name (the exact collision the tool prevents, in its "fleet of parallel agents" use case). Reproduced every trial. | Critical | `94840bf` |
| 3 | Linked worktrees didn't inherit the (gitignored) config → `up`/`db` failed with "no backend/database configured." The per-worktree workflow was broken by default. | High | `627366c` |
| 5 | A repo path containing a **space** truncated `PRIMARY` (`awk '{print $2}'`), so the primary checkout lost index 0 — nonzero ports, and a suffixed DB instead of the shared one. Common on macOS / cloud-synced dirs. | High | `94840bf` |
| 9 | `ate up backend` (scope backend/none) **exited 1 on success** — a falsy trailing test under `set -e`. Broke `ate up backend && …` and CI. | High | `6da2b8a` |
| 7 | `up` reported "still starting (first run can be slow)" even when the launched process had already **died** (bad command, missing dep, crash) — the core diagnosability gap for "can't get it working." | Medium | `ae07c0e` |
| 10 | `move` orphaned the old slot's servers: it told you to run `down` afterward, but `down` resolves the *new* index and never reached them. | Medium | `02be8c9` |
| 6 | `move`/`up` assigned ports > 65535 for a large index, dying on an opaque engine error instead of refusing. | Low | `d5f0a7c` |
| 8 | `down` could kill a **recycled** pid (id reused after the original died). | Low | `37f6cb0` |

### Fix approaches, briefly

- **#2** — `down` now enumerates the full process tree under each root (port holders
  + recorded wrapper pid) from a single portable `ps` snapshot *before* killing, then
  `SIGTERM`→`SIGKILL`; no port-tool dependency.
- **#4** — an atomic `mkdir` lock (portable; `flock` is Linux-only) + double-checked
  re-read around the scan-append in `resolve_index`.
- **#3** — `load_config` falls back to `<primary>/ataegina.config.sh` (the worktree's
  own config still wins).
- **#5** — parse `git worktree list --porcelain` with `sed`, not `awk '{print $2}'`.
- **#9** — explicit `return 0` in `cmd_up`.
- **#7** — `ate_report_ready` `kill -0`s the launched pid and reports "FAILED to
  start — see <log>" for a dead one.
- **#10** — `move` stops the old slot itself, before rewriting the registry.
- **#6** — a range guard in `move` and `up`.
- **#8** — record the launched pid's start-time at `up`, verify it at `down`.

## Test coverage added

The suite grew **44 → 110 hermetic tests**, plus opt-in tiers that start real
processes and hit real database engines (see [`../CONTRIBUTING.md`](../CONTRIBUTING.md)):

- **Real `up`/`down`** for **python, node, go, ruby** backends (go/ruby exercise
  multi-level process trees), env injection, and re-`up` idempotency.
- **Real per-worktree databases** against live **postgres, mysql, mariadb** (docker)
  and **sqlite**: create/drop/isolation, primary-drop refusal, and `up` auto-create.
- **Full two-worktree end-to-end**: distinct ports + own databases, simultaneously.
- **Real frontend-scope** borrow of the shared backend; real `logs`; `move`; `prune`
  (index recycling); concurrency; spaced-path; exit-code; diagnostics; port-bounds;
  pid-reuse.

## Red-teaming the tests

Pushing back on the tests caught real problems in them, not just in the launcher:

- The concurrency regression test was **flaky** (a single burst caught the race only
  3/5 runs). Strengthened to 12 worktrees × 5 bursts → 5/5 catch, 5/5 pass.
- The mysql integration test **false-failed** because `mysqladmin ping` answers before
  the server accepts DDL. Readiness changed to a real `SELECT 1` (pass-or-skip).
- The stack-detection matrix was **mutation-verified**: breaking one detector failed
  exactly its test and nothing else — real catchers, not tautologies.

## Verified correct (no defect)

`config set/get/unset` round-trips every tricky value (spaces, quotes, `;`, `&&`,
`$(...)`, `$VAR`) with no shell injection; `init` stack detection across
next/vite/cra + uv/django/rails/node/nest/go; idempotent `up`; per-repo registry
isolation; index stickiness and recycling.
