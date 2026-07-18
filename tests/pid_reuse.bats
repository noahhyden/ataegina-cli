#!/usr/bin/env bats
# Regression: `down` must not kill a RECYCLED pid. A pid recorded at `up` can, after
# that process dies, be reused by the OS for an unrelated process before `down` runs;
# since `down` now reaps the recorded pid's whole tree, that would take down the
# innocent process. `up` records the pid's start-time; `down` skips a recorded pid
# whose current start-time no longer matches. These tests fabricate both cases.

load helper

MARK="ate_reuse_marker_44f1"

setup()    { common_setup; integration_only; }
teardown() {
  pkill -f "$MARK" 2>/dev/null || true
  common_teardown
}

# Log dir for worktree index 1 under the helper's LOG_DIR_BASE.
wt_logdir() { printf '%s\n' "$ATE_TMP/logs/ate-wt1"; }

@test "down leaves an innocent process alone when the recorded pid was recycled" {
  local repo wt innocent ld
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='true'"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"
  run ate ports   # assign index 1

  # An unrelated, long-lived process that holds no port.
  bash -c "sleep 300" "$MARK" &
  innocent=$!

  # Fabricate a stale pidfile that points at it with a NON-matching start-time,
  # i.e. as if the original owner had died and this pid got recycled.
  ld="$(wt_logdir)"; mkdir -p "$ld"
  echo "$innocent" > "$ld/backend.pid"
  echo "Thu Jan  1 00:00:00 1970" > "$ld/backend.pidstart"

  ate down backend >/dev/null 2>&1 || true
  sleep 1
  # The guard skipped the recycled pid: the innocent process is still alive.
  kill -0 "$innocent" 2>/dev/null
}

@test "down still kills the recorded pid when its start-time matches (our process)" {
  local repo wt mine ld
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='true'"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"
  run ate ports

  bash -c "sleep 300" "$MARK" &
  mine=$!

  ld="$(wt_logdir)"; mkdir -p "$ld"
  echo "$mine" > "$ld/backend.pid"
  # Record its REAL start-time, as `up` would.
  ps -o lstart= -p "$mine" 2>/dev/null | sed 's/^ *//;s/ *$//' > "$ld/backend.pidstart"

  ate down backend >/dev/null 2>&1 || true
  sleep 1
  # Start-time matched -> adopted as a kill root -> the process is gone.
  ! kill -0 "$mine" 2>/dev/null
}
