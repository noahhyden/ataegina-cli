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

@test "doctor: a worktree with no registry entry yet is warned" {
  cd "$REPO"
  # A forced index is returned by resolve_index WITHOUT registering it, so this
  # tree has no registry row — exercising the 'none for this tree yet' branch.
  run_doctor ATE_INDEX=7
  echo "$output" | grep -qi "registry entry: none for this tree yet"
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

@test "doctor: a config-redefined FRONTEND start hook is recognized as custom" {
  write_config "$REPO" "ate_start_frontend() { echo my-custom-frontend; }"
  cd "$REPO"
  run_doctor
  echo "$output" | grep -qi "custom ate_start_frontend hook"
}

@test "doctor: an unknown DB_KIND with no create command is warned" {
  write_config "$REPO" "DB_NAME=app" "DB_KIND=weirdengine"
  cd "$REPO"
  run_doctor
  echo "$output" | grep -qi "no create command for DB_KIND"
}

@test "doctor: launcher reachable as 'ataegina' under a different invoked name" {
  local bin="$ATE_TMP/bin"; mkdir -p "$bin"
  cp "$ATE_SCRIPT" "$bin/ataegina"; chmod +x "$bin/ataegina"
  # A uniquely-named invocation (not on PATH) so `command -v <self>` misses but
  # `command -v ataegina` hits -> the "on PATH as ataegina" branch.
  cp "$ATE_SCRIPT" "$ATE_TMP/ate-cov-probe"; chmod +x "$ATE_TMP/ate-cov-probe"
  cd "$REPO"
  run env PATH="$bin:$PATH" ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" bash "$ATE_TMP/ate-cov-probe" doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "on PATH as ataegina"
}

@test "doctor: a config-defined ate_doctor hook runs last" {
  write_config "$REPO" "ate_doctor() { echo CUSTOM-DOCTOR-CHECK; }"
  cd "$REPO"
  run_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CUSTOM-DOCTOR-CHECK"
}
