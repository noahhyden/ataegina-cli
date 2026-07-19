#!/usr/bin/env bats
# resolve_scope branches not hit elsewhere: a declared `scope:` line in
# $ATE_TASK_FILE, and ATE_SCOPE_AUTO=0 (auto-detect disabled -> both). Both only
# apply to a NON-primary worktree (index != 0). Hermetic (`true` servers, none tool).

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

@test "up honors a declared scope: line in ATE_TASK_FILE" {
  local wt; wt="$(add_worktree "$REPO" wtDecl)"
  printf 'scope: frontend\n' > "$ATE_TMP/task.md"
  up_wt "$wt" ATE_TASK_FILE="$ATE_TMP/task.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "scope: frontend"
}

@test "up with ATE_SCOPE_AUTO=0 on a worktree falls back to both" {
  local wt; wt="$(add_worktree "$REPO" wtAutoOff)"
  up_wt "$wt" ATE_SCOPE_AUTO=0
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "scope: both"
}
