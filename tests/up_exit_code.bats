#!/usr/bin/env bats
# Regression for the set -e + falsy-last-statement trap in cmd_up: `up` must exit 0
# on a successful start even when NO frontend is launched (scope backend / none),
# where cmd_up's last statement `[ "$did_fe" = 1 ] && ...` is false. Before the fix
# cmd_up returned that 1 and set -e aborted `up` with exit 1 despite success — which
# breaks `ate up backend && ...` and any CI/script gating on the exit code. Portable
# (no port tool or real server needed): runs under the suite default ATE_PORT_TOOL=none.

load helper

setup()    { common_setup; }
teardown() {
  pkill -f 'sleep 424242' 2>/dev/null || true
  common_teardown
}

@test "up backend exits 0 when only the backend starts (no frontend)" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='sleep 424242'"
  cd "$repo"
  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  ate down backend >/dev/null 2>&1 || true
}

@test "up --scope none exits 0 (nothing started)" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='sleep 424242'"
  wt="$(add_worktree "$repo" wt)"
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
  cd "$wt"
  run ate up --scope none
  [ "$status" -eq 0 ]
}
