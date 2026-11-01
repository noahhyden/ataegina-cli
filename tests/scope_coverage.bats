#!/usr/bin/env bats
# resolve_scope branch not hit elsewhere: ATE_SCOPE_AUTO=0 (auto-detect disabled -> both), which only applies to a NON-primary worktree. Hermetic.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  write_config "$REPO" \
    "FRONT_PORT_BASE=55100" "BACK_PORT_BASE=56100" \
    "FRONTEND_DIR='.'" "FRONTEND_CMD='true'" \
    "BACKEND_DIR='.'"  "BACKEND_CMD='true'"
}
teardown() { common_teardown; }

# up on a worktree $1 with the given extra env, returning $output/$status.
up_wt() {
  local wt="$1"; shift
  cp "$REPO/ataegina.config.sh" "$wt/ataegina.config.sh"
  cd "$wt"
  run env ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" "$@" bash "$ATE_SCRIPT" up
}

@test "up with ATE_SCOPE_AUTO=0 on a worktree falls back to both" {
  local wt; wt="$(add_worktree "$REPO" wtAutoOff)"
  up_wt "$wt" ATE_SCOPE_AUTO=0
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "scope: both"
}
