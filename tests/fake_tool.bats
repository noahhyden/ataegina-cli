#!/usr/bin/env bats
# Behavioral probes driven by the parametrized FAKE tool (tests/fake/mockserver.sh).
# Each test dials exactly ONE property of the fake server and asserts ataegina's
# reaction, covering conditions a real framework's dev server can't reproduce
# reliably: immediate crash, slow boot, worker trees that never hold the socket,
# a process that ignores SIGTERM, voluntary exit, and env injection.
#
# Integration-tier: these start REAL processes and bind REAL ports, so they are
# gated behind ATE_TEST_INTEGRATION (same ethos as up_down_real.bats).

load helper

MOCK="$BATS_TEST_DIRNAME/fake/mockserver.sh"

setup() {
  # CRITICAL: assign the unique tag FIRST, before any `skip` can return early.
  # bats runs teardown() even for skipped tests, and teardown reaps by $TAG. If
  # TAG were still empty there, `pkill -f "$TAG"` becomes `pkill -f ""` — an empty
  # pattern matches EVERY command line, so it would SIGTERM every process the user
  # owns (shell, editor, desktop session). That is a machine-freezing footgun; the
  # tag must exist before the first skip, and teardown must refuse an empty tag.
  TAG="mock_$$_${BATS_TEST_NUMBER}"
  common_setup
  integration_only
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  if command -v lsof >/dev/null 2>&1; then export ATE_PORT_TOOL=lsof
  elif command -v ss >/dev/null 2>&1; then export ATE_PORT_TOOL=ss
  else skip "no port tool (lsof/ss) available"; fi
  # Per-test port bases (high + offset by test number) so no two tests ever
  # contend for the same socket — kills sequential-reuse flakiness dead.
  FE_BASE=$((46100 + BATS_TEST_NUMBER))
  BE_BASE=$((47100 + BATS_TEST_NUMBER))
}
teardown() {
  # Reap only THIS test's tree via the guarded helper, which refuses an empty or
  # short tag (so a session-killing `pkill -f ""` can never happen). No test file
  # calls pkill/pgrep directly — harness_safety.bats enforces that.
  ate_reap_tag "${TAG:-}"
  common_teardown
}

# Independent listening check (does not use ataegina's own detection).
listening() {
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:"$1" >/dev/null 2>&1
  else ss -ltn "sport = :$1" 2>/dev/null | grep -q ":$1"; fi
}
wait_listening() { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" && return 0; sleep 0.25; i=$((i+1)); done; return 1; }
wait_free()      { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" || return 0; sleep 0.25; i=$((i+1)); done; return 1; }
# Gating "port is NOT listening" — see refute_* in helper.bash for why `! listening`
# would be a silent no-op mid-test.
refute_listening() { if listening "$1"; then return 1; fi; return 0; }

# Count live processes carrying this test's tag (the whole mock tree), via the
# guarded helper (refuses an empty/short tag, so no bare `pgrep -f ""` is possible).
tree_count() { ate_count_tag "${TAG:-}"; }
wait_tree_gone() { local i=0; while [ "$i" -lt 40 ]; do [ "$(tree_count)" = 0 ] && return 0; sleep 0.25; i=$((i+1)); done; return 1; }

# Configure a repo whose backend is the fake tool, carrying $extra_env into it.
# The tag is passed as a trailing ARGV token (not just an env var) so EVERY node
# in the launched tree — the sh/bash wrapper included, not only the workers and
# the python listener — carries it in its command line. Without this the wrapper
# (the one process that can ignore SIGTERM) is invisible to pgrep, which would
# make the SIGKILL-escalation test a false pass.
mock_repo() {
  local repo="$1"; shift
  make_repo "$repo" >/dev/null
  write_config "$repo" \
    "FRONT_PORT_BASE=$FE_BASE" "BACK_PORT_BASE=$BE_BASE" \
    "BACKEND_DIR='.'" \
    "BACKEND_CMD='bash \"$MOCK\" $TAG'" \
    "BACKEND_ENV='$*'"
}

# --- healthy baseline -------------------------------------------------------

@test "fake: healthy backend binds the derived port; down frees it" {
  local repo="$ATE_TMP/repo"
  mock_repo "$repo" "MOCK_TAG=$TAG"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening "$BE_BASE"          # primary index 0 -> BE_BASE+0

  ate down backend
  wait_free "$BE_BASE"
}

# --- both sides at once -----------------------------------------------------

@test "fake: up both binds frontend + backend on distinct ports; down both reaps both" {
  local repo="$ATE_TMP/repo"
  make_repo "$repo" >/dev/null
  # Same fake tool on BOTH sides; ataegina exports PORT per side (FRONTEND_PORT vs
  # BACKEND_PORT), so each instance binds its own slot. Distinct sub-tags (both
  # contain $TAG, so the tag reap/count still sees them) keep the sides separable.
  write_config "$repo" \
    "FRONT_PORT_BASE=$FE_BASE" "BACK_PORT_BASE=$BE_BASE" \
    "FRONTEND_DIR='.'" "FRONTEND_CMD='bash \"$MOCK\" ${TAG}-fe'" "FRONTEND_ENV='MOCK_TAG=${TAG}-fe'" \
    "BACKEND_DIR='.'"  "BACKEND_CMD='bash \"$MOCK\" ${TAG}-be'"  "BACKEND_ENV='MOCK_TAG=${TAG}-be'"
  cd "$repo"

  run ate up both --scope both
  [ "$status" -eq 0 ]
  wait_listening "$FE_BASE"
  wait_listening "$BE_BASE"
  listening "$FE_BASE"        # both held simultaneously == no collision
  listening "$BE_BASE"

  run ate down both
  [ "$status" -eq 0 ]
  wait_free "$FE_BASE"
  wait_free "$BE_BASE"
  wait_tree_gone
  [ "$(tree_count)" = 0 ]     # BOTH trees reaped
}

# --- idempotency ------------------------------------------------------------

@test "fake: re-up is idempotent — a second 'up' says already-up and spawns no duplicate" {
  local repo="$ATE_TMP/repo"
  mock_repo "$repo" "MOCK_TAG=$TAG"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening "$BE_BASE"
  local before; before="$(tree_count)"
  [ "$before" -ge 2 ]                 # at least the wrapper + the listener

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already up"
  # The port was already held, so no second server may be launched.
  [ "$(tree_count)" -le "$before" ]

  ate down backend
  wait_free "$BE_BASE"
  wait_tree_gone
  [ "$(tree_count)" = 0 ]
}

@test "fake: up launches no duplicate when the slot port is already held (foreign holder)" {
  local repo="$ATE_TMP/repo"
  mock_repo "$repo" "MOCK_TAG=$TAG"
  cd "$repo"
  # Pre-occupy the backend slot with an INDEPENDENT holder ataegina never launched
  # (a separate mock carrying a squatter sub-tag, so teardown's tag reap still
  # catches it). ataegina cannot tell this from its own server — it only sees the
  # port busy — but the defensible, lockable property is: it must NOT start a
  # SECOND server on top of a held slot.
  MOCK_TAG="${TAG}-squat" MOCK_PORT="$BE_BASE" bash "$MOCK" "${TAG}-squat" >/dev/null 2>&1 &
  wait_listening "$BE_BASE"
  local before; before="$(tree_count)"     # the squatter tree (its tag contains $TAG)

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already up"    # (characterizes: foreign holder reads as up)
  [ "$(tree_count)" -le "$before" ]         # no duplicate server launched on the slot
  # NB: `ate down` here would kill the FOREIGN holder — a documented dev-possibility,
  # deliberately NOT asserted so a future "leave foreign processes alone" fix is free
  # to change it. Teardown reaps the squatter via its tag.
}

@test "fake: re-up DURING a slow boot does not double-launch (boot-window idempotency)" {
  local repo="$ATE_TMP/repo"
  # Boot 14s is well beyond the ~8s readiness window, so the first `up` returns
  # "still starting" with the port NOT yet bound — the exact window in which a
  # second `up` used to double-launch (guarding only on the port), orphaning the
  # first wrapper and overwriting its pidfile so `down` could not reap it.
  mock_repo "$repo" "MOCK_TAG=$TAG; MOCK_BOOT_DELAY=14"
  cd "$repo"
  # Count only launch WRAPPERS (the `…/mockserver.sh <tag>` process + its sh parent),
  # not the eventual listener — so this measures how many servers were launched.
  wrapper_count() { ate_count_tag "mockserver.sh $TAG"; }

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "still starting"
  local after1; after1="$(wrapper_count)"
  [ "$after1" -ge 1 ]

  run ate up backend --scope backend            # re-up while the first is still booting
  [ "$status" -eq 0 ]
  [ "$(wrapper_count)" -le "$after1" ]           # no SECOND launch

  ate down backend
  wait_free "$BE_BASE"
  wait_tree_gone
  [ "$(tree_count)" = 0 ]                         # nothing leaked
}

# --- readiness: crash vs slow boot -----------------------------------------

@test "fake: an immediately-crashing backend is reported FAILED (not 'still starting')" {
  local repo="$ATE_TMP/repo"
  mock_repo "$repo" "MOCK_TAG=$TAG; MOCK_CRASH=1"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  # The launch pid exits before binding; readiness must call it out as FAILED.
  echo "$output" | grep -qi "FAILED to start"
  refute_listening "$BE_BASE"
}

@test "fake: a slow-booting backend is reported 'still starting' (not FAILED)" {
  local repo="$ATE_TMP/repo"
  # Boot delay comfortably beyond the ~8s readiness window.
  mock_repo "$repo" "MOCK_TAG=$TAG; MOCK_BOOT_DELAY=15"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "still starting"
  # A slow-but-alive server must NOT be misreported as dead.
  refute_output_has "FAILED to start"

  ate down backend >/dev/null 2>&1 || true
  wait_tree_gone
}

@test "fake: a daemonize-style start (wrapper exits before the child binds) is not reported FAILED" {
  local repo="$ATE_TMP/repo"
  # Wrapper exits at 0; the (orphaned) listener binds 1.5s later. The recorded
  # launch pid is dead before the port is up — a dead launcher is NOT proof of
  # failure when it forked the real server (daemonize). Readiness must give the
  # port a grace window instead of declaring FAILED the instant the pid is gone.
  mock_repo "$repo" "MOCK_TAG=$TAG; MOCK_WRAPPER_EXITS=1; MOCK_WRAPPER_EXIT_DELAY=0; MOCK_LISTENER_BIND_DELAY=1.5"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  refute_output_has "FAILED to start"   # the server really comes up
  wait_listening "$BE_BASE"

  ate down backend
  wait_free "$BE_BASE"
  wait_tree_gone
  [ "$(tree_count)" = 0 ]
}

# --- process-tree reaping (the orphan-leak guarantee) ----------------------

@test "fake: down reaps worker children that never held the port (no orphan leak)" {
  local repo="$ATE_TMP/repo"
  mock_repo "$repo" "MOCK_TAG=$TAG; MOCK_CHILDREN=3"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening "$BE_BASE"
  # wrapper + 3 workers + listener all alive
  [ "$(tree_count)" -ge 4 ]

  ate down backend
  wait_free "$BE_BASE"
  wait_tree_gone
  [ "$(tree_count)" = 0 ]
}

@test "fake: down reaps a deep tree (workers + grandchildren)" {
  local repo="$ATE_TMP/repo"
  mock_repo "$repo" "MOCK_TAG=$TAG; MOCK_CHILDREN=2; MOCK_GRANDCHILD=1"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening "$BE_BASE"
  [ "$(tree_count)" -ge 5 ]   # wrapper + 2 workers + 2 grandchildren + listener
  # Prove the tree really has DEPTH (grandchild's parent is a worker, not the
  # wrapper) — otherwise this degrades into a breadth-only test and ate_pid_tree's
  # descent is never exercised.
  ate_tag_is_child_of "${TAG}-grandchild" "${TAG}-worker"

  ate down backend
  wait_tree_gone
  [ "$(tree_count)" = 0 ]
}

# --- signal escalation ------------------------------------------------------

@test "fake: down escalates to SIGKILL for a backend that ignores SIGTERM" {
  local repo="$ATE_TMP/repo"
  mock_repo "$repo" "MOCK_TAG=$TAG; MOCK_IGNORE_SIGTERM=1"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening "$BE_BASE"

  ate down backend
  # Polite SIGTERM is ignored by the wrapper; ataegina must escalate. Port freed
  # and tree gone are the observable proof the escalation worked.
  wait_free "$BE_BASE"
  wait_tree_gone
  [ "$(tree_count)" = 0 ]
}

# --- port holder outlives the recorded launch pid --------------------------

@test "fake: down reaps the orphaned holder even after the recorded launch pid has died" {
  local repo="$ATE_TMP/repo"
  mock_repo "$repo" "MOCK_TAG=$TAG; MOCK_WRAPPER_EXITS=1; MOCK_WRAPPER_EXIT_DELAY=1"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening "$BE_BASE"

  # Deterministically wait until the pid ataegina RECORDED at launch is dead, so
  # `down` must reap via the port holder alone. This is the case that aborted down
  # under `set -e`+`pipefail`: `ps` on a dead pid fails the pipeline in
  # ate_pid_starttime, failing the `got="$(...)"` assignment and killing down
  # before it reaped anything (leaking the port). Waiting for the death makes the
  # regression deterministic instead of racing the wrapper's exit.
  local pidfile="$ATE_TMP/logs/ate-wt0/backend.pid" lpid i=0
  lpid="$(cat "$pidfile" 2>/dev/null || true)"
  [ -n "$lpid" ]
  while [ "$i" -lt 40 ] && kill -0 "$lpid" 2>/dev/null; do sleep 0.25; i=$((i+1)); done
  refute_alive "$lpid"                     # recorded launch pid is now dead

  run ate down backend
  [ "$status" -eq 0 ]                       # down must not abort under set -e/pipefail
  echo "$output" | grep -qi "stopped on"    # and must actually reap the holder
  wait_free "$BE_BASE"
  wait_tree_gone
  [ "$(tree_count)" = 0 ]
}

# --- env injection reaches the live process --------------------------------

@test "fake: injected BACKEND_URL and a custom BACKEND_ENV reach the fake process" {
  local repo="$ATE_TMP/repo" out="$ATE_TMP/env.out"
  mock_repo "$repo" "MOCK_TAG=$TAG; MOCK_ENV_OUT=$out; MOCK_CUSTOM=hi_\$BACKEND_PORT"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening "$BE_BASE"
  ate down backend >/dev/null 2>&1 || true

  [ -f "$out" ]
  grep -q "BACKEND_URL=http://localhost:$BE_BASE" "$out"
  grep -q "MOCK_CUSTOM=hi_$BE_BASE" "$out"
}

@test "fake: a BACKEND_ENV value with spaces and '=' (double-quoted) reaches the process intact" {
  local repo="$ATE_TMP/repo" out="$ATE_TMP/env.out"
  # ataegina parses *_ENV via `eval "export $(… | tr '\n;' ' ')"`. A double-quoted
  # value must survive that eval with its spaces and embedded '=' intact — the
  # realistic case being a flag string or a URL with query params.
  mock_repo "$repo" "MOCK_TAG=$TAG; MOCK_ENV_OUT=$out; MOCK_CUSTOM=\"hello world=x&y=z\""
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening "$BE_BASE"
  ate down backend >/dev/null 2>&1 || true

  [ -f "$out" ]
  grep -q "MOCK_CUSTOM=hello world=x&y=z" "$out"
}
