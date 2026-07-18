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

## Open dev-possibilities (characterized, not "bugs")

These are defensible current behaviors, documented so a future change is a deliberate
choice rather than a surprise. Deliberately NOT locked into assertions.

### A. `up` cannot distinguish its own server from a foreign holder
When any process already holds the derived slot port, `ate up` prints
"backend already up on :PORT" and "ready" — even if ataegina never launched it. It
only checks whether the port is listening, not whether the listener is its own. Idea:
cross-check the recorded pidfile and warn ("port held by a process ataegina did not
start") instead of implying success. Covered defensively by "up launches no duplicate
when the slot port is already held".

### B. `ate down` kills a foreign process on the slot
`_ate_stop_port` reaps whatever holds the derived port, including a process ataegina
never launched. Note the asymmetry: `down` carefully avoids killing a *recycled
recorded pid* (the start-time guard) yet freely kills an unrelated port holder. The
design premise is "the slot belongs to this worktree," so clearing it is somewhat
intentional — but killing an unrelated process is surprising collateral. Idea: restrict
killing to the recorded process tree, or at least warn when the port holder isn't in
ataegina's records.
