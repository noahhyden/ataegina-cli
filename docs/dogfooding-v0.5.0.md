# Dogfooding report: ataegina v0.5.0

A hands-on validation of the v0.5.0 launcher installed on a real workstation
(macOS, system bash 3.2, `lsof` present) and exercised across throwaway repos
and 23 pre-existing real repositories. The goal was to confirm the tool performs
as intended end to end, not just that the unit suite passes.

**Verdict: the core is solid.** Every collision-free primitive the tool exists
to provide -- per-worktree index assignment, derived non-colliding ports,
per-worktree database deconfliction with real env injection, process lifecycle,
and the registry -- worked correctly and robustly, including several worktrees
running full stacks simultaneously. Dogfooding did surface **two real crashes in
`ataegina init`'s stack detection** (both `set -e` fragilities, neither in the
launcher hot path). Both were root-caused, fixed, and covered by new regression
tests in the same change set. A handful of non-blocking limitations are
documented at the end.

## Method and isolation

So the host's real environment was never perturbed:

- Installed v0.5.0 as the active `ate` on `PATH` and verified `ate --version`,
  checksum integrity (`shasum -c`), and that zero dispatcher symbols remain.
- All tests ran with an **isolated registry** (`ATE_REGISTRY_DIR` pointed at a
  scratch dir), so the real `~/.config/ataegina` registry was never written.
  Confirmed after the run: the only real registry entry (a pre-existing project)
  was untouched.
- Throwaway stacks used **high port bases (17000 / 18000)** to avoid colliding
  with anything already listening on the machine.
- Real-repo coverage used only `init --dry-run` (read-only; writes nothing) and
  read-only `doctor`. No `up`, no database writes, no service starts in real
  repos. Verified afterward that no `ataegina.config.sh` was created or modified
  in any real repo.
- Real databases were never touched; DB tests used sqlite files in scratch and a
  postgres URL **template** (asserted by value, not by connecting).

Real repositories are referred to below only by detected stack, never by name.

## Results by area

| Area | Result | Evidence |
|---|---|---|
| Install / version / checksum | PASS | `ate --version` -> `0.5.0`; `shasum -c` OK; 0 dispatcher symbols |
| Index assignment + derived ports | PASS | primary `#0` (17000/18000), worktrees `#1`/`#2` (17001/18001, 17002/18002) |
| Concurrent multi-worktree stacks | PASS | two worktrees up at once; all four ports served HTTP 200, no collision |
| Index stickiness | PASS | a worktree kept index `#1` across repeated runs |
| `prune` + index recycle | PASS | stale `#2` flagged then pruned; next new worktree reused freed `#2` |
| `ATE_INDEX` override | PASS | forced `#9` -> frontend on 17009 for one run |
| `up` readiness signal | PASS | "backend ready ->", "frontend ready ->" only after the port actually bound |
| `logs` | PASS | `--no-follow` dumped both streams with `==> file <==` banners |
| `down` + orphan safety | PASS | both ports freed; both launched PIDs reaped; no stray processes |
| Per-worktree DB derivation | PASS | primary keeps unsuffixed name; worktree `#N` gets `<name>_wt<N>` |
| **DB env injection (live process)** | PASS | primary process saw `DATABASE_URL=.../shop`; worktree saw `.../shop_wt1` |
| `db drop` safety | PASS | primary drop refused; worktree drop removed only its file |
| Scope-aware `up` | PASS | frontend-only -> `frontend` (+ auto-started a local backend since the shared one was down); backend-only -> `backend`; no diff -> `none` nudged to `both` with a hint |
| `config get/set/unset` | PASS | round-trips; `set` stored values single-quoted so `$ATE_DB_NAME` stayed literal; `unset` reverted to default |
| `doctor` | PASS | reported launcher/version, index, registry, config, hooks, database, resolved scope, port tool, port availability, URLs |
| Edge cases | PASS | bare `ate` -> usage (exit 0); unknown cmd -> usage (exit 2); `run`/`status` -> exit 2 (dispatcher gone); outside a repo -> clear error (exit 1); `ATE_PORT_TOOL=none` -> degraded warning, still functional |
| `init` detection over 23 real repos | PASS (after fixes) | recognized uv/Python, Next.js, Vite, full-stack combos; correctly flagged an unrecognized frontend and a dev script with a pinned port |

### Highlight: per-worktree database injection works for real

The headline differentiator was validated empirically, not just by reading
`db url`. A throwaway backend whose start command was `printenv DATABASE_URL`
recorded what the launcher actually exported into the process:

- Primary (`#0`): `postgres://localhost:5432/shop`
- Worktree (`#1`): `postgres://localhost:5432/shop_wt1`

Each worktree's process really does boot against its own database name.

## Bugs found and fixed

Both are `set -e` / `pipefail` fragilities in `init`'s detection. Neither touches
the launcher (`up`/`down`/`ports`/`db`/`logs`); both are pre-existing (not
introduced by the dispatcher removal). Both are fixed in this change set with
regression tests in `tests/init.bats`.

### Bug 1 -- silent crash on a `package.json` with no `dev` script

`ataegina init` on a Node CLI/library (a `package.json` with no `"dev"` script)
exited `1` with **no output at all**. Root cause: `pkg_dev_script` runs
`grep -oE '"dev"...' | head | sed`; with no match, `grep` exits 1, and under
`set -o pipefail` the pipeline fails, so the `dev="$(pkg_dev_script ...)"`
assignment fails and `set -e` aborts the whole command before anything is
printed. Fix: tolerate a no-match (`|| true`) so an absent dev script is an
empty-but-successful result, which the caller already handles.

### Bug 2 -- `init` exits 1 (after printing) when the last emitted line is a falsy test

More pervasive: `init` printed the **entire correct config** but still exited
`1` whenever generation ended on a falsy test -- e.g. a detected backend with no
`BACKEND_ENV`, where the final statement in `emit_config` is
`[ -n "$BE_ENV" ] && printf ...`. That test returns 1, so `emit_config` returns
1, and `set -e` aborts `cmd_init` at the call site before it can `return 0` (or,
for a real `init`, before it prints "wrote ..." -- the file was written but the
command reported failure). Across the 23 real repos, most `init --dry-run`
invocations were exiting 1 for this reason. Fix: end `emit_config` with an
explicit `return 0`. After the fix, all 23 real repos exit 0 and write nothing
on `--dry-run`; a real `init` writes the config and exits 0.

## Known limitations (non-blocking, worth documenting)

1. **`ataegina.config.sh` is a committed, per-branch file.** Setting DB/stack
   config on one branch does not appear in worktrees branched earlier. During
   testing, worktrees created before a `config set` reported "no database
   configured" until a worktree was branched after the config commit. This is
   expected git behavior, but it is a real onboarding gotcha for the
   per-worktree-DB workflow: commit config on the base branch first, or use the
   global (`$XDG_CONFIG_HOME`) config. Worth a sentence in the README.
2. **Backend detection recognizes `uv` only (requires `uv.lock`).** A Python
   backend using poetry / pdm / pip+`requirements.txt`, or a bare `pyproject.toml`
   without `uv.lock`, is reported "none found". Defensible (avoids guessing), but
   it is the most likely "why didn't it detect my backend" surprise.
3. **Unrecognized frontends** (a `package.json` with no known framework dep) are
   correctly reported as "unrecognized frontend ... (TODO: fill FRONTEND_CMD)"
   rather than guessing -- good behavior, just noting the coverage edge.
4. **Latent `pipefail` risk in the `ss` port-detection fallback.** The `ss`
   branch pipes through `grep -v`, which returns 1 when it filters everything
   out; under `pipefail` this could fail the surrounding assignment on Linux
   boxes without `lsof`. Not reproduced here (the host uses `lsof`), but the
   same class as the two bugs above and worth an audit / a defensive `|| true`.

## Bottom line

The collision-free worktree-stack machinery -- the actual product -- performed
exactly as intended under real use, including the database deconfliction that is
the project's main differentiator. The issues found were both in `init`'s
convenience detection, both `set -e` fragilities, both now fixed and regression
tested (suite is now 44 tests, all green; shellcheck clean). Recommendation:
keep dogfooding; the `init` fixes here should ship; address the per-branch-config
documentation and consider broadening backend detection before any wide release.
