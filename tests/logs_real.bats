#!/usr/bin/env bats
# Real `logs`: a started backend's stdout lands in this tree's per-worktree log, and
# `ate logs backend --no-follow` streams it back. Uses a real launched process.

load helper

LOGMARK="ate_logs_marker_71b3"

setup()    { common_setup; integration_only; }
teardown() {
  pkill -f "$LOGMARK" 2>/dev/null || true
  common_teardown
}

@test "logs --no-follow shows the backend's own output" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  # Print a marker (captured into backend.log), then stay alive.
  write_config "$repo" "BACKEND_DIR='.'" \
    "BACKEND_CMD='echo READY_$LOGMARK; sleep 30 # $LOGMARK'"
  cd "$repo"
  ate up backend --scope backend >/dev/null 2>&1 || true
  sleep 1   # let the echo flush to the log file

  run ate logs backend --no-follow -n 50
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "READY_$LOGMARK"

  ate down backend >/dev/null 2>&1 || true
}

@test "logs errors clearly when there is no log yet" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='true'"
  cd "$repo"
  # No `up` has run, so no backend log exists.
  run ate logs backend --no-follow
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "no backend log"
}
