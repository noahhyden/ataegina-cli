#!/usr/bin/env bats
# Regression for the dead-vs-slow diagnosability gap: `up`'s readiness report used to
# say "still starting (first run can be slow)" for EVERY server that wasn't listening
# yet — including one that had already died (bad command, missing dep, crash). It now
# checks whether the launched pid is still alive and reports "FAILED to start" for a
# dead one, while a slow-but-alive server still reads "still starting". Portable
# (default ATE_PORT_TOOL=none; the pid-liveness check is independent of the port tool).

load helper

SLOWMARK="ate_diag_slow_marker"

setup()    { common_setup; integration_only; }
teardown() {
  pkill -f "$SLOWMARK" 2>/dev/null || true
  common_teardown
}

@test "up reports FAILED (not 'still starting') when the command dies immediately" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='this_binary_does_not_exist_xyzzy'"
  cd "$repo"
  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "FAILED to start"
  refute_output_has "still starting"
}

@test "up says 'still starting' (not FAILED) for a slow but alive server" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='sleep 20 # $SLOWMARK'"
  cd "$repo"
  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "still starting"
  refute_output_has "FAILED to start"
  ate down backend >/dev/null 2>&1 || true
}
