# Fake-tool harness — findings

The `tests/fake/` harness (a parametrized fake dev server `mockserver.sh` and a fake
DB CLI `mockdb.sh`, driven by `tests/fake_tool.bats` and `tests/db_up.bats`) exists to
push ataegina through conditions a real framework's dev server can't reproduce on
demand: immediate crash, slow boot, worker trees, a process that ignores SIGTERM, a
launcher that forks a daemon and exits, a failing DB engine, a foreign port holder.

This is the running log of what it turned up.

## Running the harness

```bash
# Hermetic (no processes/ports/network) — the fake DB tests + the safety lint:
bats tests/db_up.bats tests/harness_safety.bats

# The fake dev-server probes start REAL processes and bind REAL ports, so they are
# gated behind ATE_TEST_INTEGRATION (like the other real-process tests). Always wrap
# in a hard timeout so a hung probe can't run away:
timeout 150 env ATE_TEST_INTEGRATION=1 bats tests/fake_tool.bats
```

Safety notes for anyone extending it:
- All process reaping goes through the guarded helpers in `tests/helper.bash`
  (`ate_reap_tag` / `ate_count_tag`), which refuse an empty/short tag — never call
  `pkill`/`pgrep` by pattern directly (a bare `pkill -f ""` matches every process
  and can kill your session). `harness_safety.bats` enforces this.
- Negative assertions must use `refute` / `refute_output_has` / `refute_alive`, not
  `! cmd` (which bats' `set -e` silently ignores). `harness_safety.bats` enforces this.

## Fixed bugs

### 1. `ate down` aborted and leaked the port holder when the recorded pid was dead
`ate_pid_starttime` ran `ps -o lstart= -p "$pid" | sed …`. Under the script's
`set -o pipefail`, a **dead** pid makes `ps -p` exit non-zero, failing the pipeline;
at the `got="$(ate_pid_starttime "$lpid")"` call site in `_ate_stop_port` that tripped
`set -e` and aborted `down` before it reaped anything — silently leaving the real port
holder running. Triggered whenever the pid ataegina recorded at launch had already
exited by teardown time (a wrapper that forks the server and exits: `uvicorn --reload`,
`next dev`, a daemonizer). Fixed by tolerating a dead pid (`{ ps …; || true; }`).
Regression: `tests/fake_tool.bats` "down reaps the orphaned holder even after the
recorded launch pid has died" (via `MOCK_WRAPPER_EXITS`).

### 2. Readiness reported FAILED for a daemonize-style start
`ate_report_ready` declared "FAILED to start" the instant the recorded launch pid was
gone. A launcher that forks the real server and exits leaves that pid dead while the
child is still binding — so a server that genuinely came up was reported failed. Fixed
by polling the port for a brief grace after the pid is seen dead before concluding
failure (a real crash still ends in FAILED; a slow server still says "still starting").
Regression: `tests/fake_tool.bats` "a daemonize-style start … is not reported FAILED"
(via `MOCK_WRAPPER_EXITS` + `MOCK_LISTENER_BIND_DELAY`).

### 3. `up` double-launched (and leaked) during the boot window
`ate_start_backend` / `ate_start_frontend` guarded only on `ate_port_listening`. During
a **slow boot** — after `up` returns "still starting" but before the server binds its
port — a second `up` saw the port free and launched a **second** server. The two race
to bind; the pidfile is overwritten with the second launch's pid; the first wrapper is
orphaned so `down` can no longer reap it — an untracked-process leak, the exact drain
the tool exists to prevent. Fixed with `_ate_launch_in_progress`: if the recorded
launch pid is still alive and still ours (same start-time guard `down` uses), the start
hooks report "already starting" and do not relaunch (a dead/pid-reused record still
allows a fresh start for crash recovery). Regression: `tests/fake_tool.bats` "re-up
DURING a slow boot does not double-launch" (via `MOCK_BOOT_DELAY` beyond the readiness
window).

## Test-suite defects found & fixed

### 3. `!`-prefixed assertions were silent no-ops
bats runs test bodies under `set -e`, but a `!`-prefixed command is exempt — so a
`! grep …` / `! kill -0 …` / `! listening …` in the MIDDLE of a body never failed the
test (it only gated when it happened to be the last line). ~10 assertions across the
suite were affected, including `config.bats`'s `! grep -q "EVIL_KEY"` (a config
injection guard). Converted all to gating helpers (`refute` / `refute_output_has` /
`refute_alive`); a `harness_safety.bats` lint now fails CI if a `!`-prefixed assertion
reappears. (All converted assertions still passed — the expectations were holding, just
unenforced.)

## Fixed bugs (continued)

### 4. `up` could not distinguish its own server from a foreign holder
When any process already held the derived slot port, `ate up` printed "backend already
up on :PORT" and "ready" — even if ataegina never launched it. It only checked whether
the port was *listening*, not whether the listener was its own. Fixed by
`_ate_port_ownership label port` (prints `ours` / `foreign` / `unknown`): it maps the
port to pid(s) and checks whether any sits inside the process tree of our
start-time-VERIFIED recorded launch. `up` now says "held by a process ataegina did not
start — not launching" for a `foreign` holder (and readiness stays silent instead of
declaring the foreign server "ready"). Crucially, a holder we *might* own but cannot
prove (unmappable pids, or a daemonize-style start whose recorded wrapper exited and
left the real server reparented to init) is `unknown`, never `foreign` — so we never
accuse our own reparented server. Regression: `tests/fake_tool.bats` "up REFUSES to
claim a foreign-held slot as its own" (and #12 daemonize still passes, proving the
conservatism holds).

### 5. `ate down` killed a foreign process on the slot
`_ate_stop_port` reaped whatever held the derived port, including a process ataegina
never launched — the asymmetric counterpart to bug 4 (`down` already avoided killing a
*recycled recorded pid* via the start-time guard, yet freely killed an unrelated port
holder). Fixed with the same `_ate_port_ownership` check: `down` now leaves a
positively-`foreign` holder alone and says so, while `down --force` (or
`ATE_DOWN_FORCE=1`) still clears the slot on demand. Ambiguous (`unknown`) cases fall
through to the normal teardown, so a reparented daemon of ours is still reaped.
Regression: `tests/fake_tool.bats` "down LEAVES a foreign slot holder alone, but
--force reaps it".
