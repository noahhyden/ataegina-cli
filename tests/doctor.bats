#!/usr/bin/env bats
# cmd_doctor diagnostic branches. Read-only; hermetic (ATE_PORT_TOOL=none).

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
}
teardown() { common_teardown; }

# Run doctor for the current dir with a clean temp registry.
run_doctor() {
  run env ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" "$@" bash "$ATE_SCRIPT" doctor
}

@test "doctor: launcher found on PATH is reported ok" {
  local bin="$ATE_TMP/bin"; mkdir -p "$bin"
  cp "$ATE_SCRIPT" "$bin/ataegina"; chmod +x "$bin/ataegina"
  cd "$REPO"
  run_doctor PATH="$bin:$PATH"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "launcher: on PATH"
}

@test "doctor: a repo with no config is flagged (run init)" {
  cd "$REPO"                                # make_repo writes no config
  run_doctor
  echo "$output" | grep -qi "no config found"
}

@test "doctor: a stale registry entry (its worktree is gone) is reported" {
  local wt; wt="$(add_worktree "$REPO" wtA)"
  ( cd "$wt" && env ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
      bash "$ATE_SCRIPT" ports >/dev/null )   # register index 1
  git -C "$REPO" worktree remove --force "$wt"
  cd "$REPO"
  run_doctor
  echo "$output" | grep -qi "stale registry entry"
}

@test "doctor: a config-redefined start hook is recognized as custom" {
  write_config "$REPO" "ate_start_backend() { echo my-custom-backend; }"
  cd "$REPO"
  run_doctor
  echo "$output" | grep -qi "custom ate_start_backend hook"
}

@test "doctor: a DB create tool that is not on PATH is warned" {
  write_config "$REPO" \
    "DB_NAME=app" "DB_KIND=custom" \
    "DB_CREATE_CMD='no_such_db_tool_zzz create'"
  cd "$REPO"
  run_doctor
  echo "$output" | grep -qi "create tool 'no_such_db_tool_zzz' not on PATH"
}

@test "doctor: warns when a pinned dev-script port would be ignored (npm run dev)" {
  mkdir -p "$REPO/frontend"
  printf '{"scripts":{"dev":"next dev -p 3000"}}\n' > "$REPO/frontend/package.json"
  write_config "$REPO" "FRONTEND_DIR='frontend'" "FRONTEND_CMD='npm run dev'"
  cd "$REPO"
  run_doctor
  echo "$output" | grep -qi "frontend port pin"
}

@test "doctor: a config-defined ate_doctor hook runs last" {
  write_config "$REPO" "ate_doctor() { echo CUSTOM-DOCTOR-CHECK; }"
  cd "$REPO"
  run_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CUSTOM-DOCTOR-CHECK"
}
