#!/usr/bin/env bats
# `ataegina env` — print this worktree's derived environment as eval-able shell.
#
# Spec: `env` emits, one assignment per line, the SAME variables `up` injects into
# your dev servers (index, ports, URLs, log dir, and — when a DB is configured —
# the per-worktree DB name + URL), so `eval "$(ataegina env)"` reproduces that
# environment in your own shell, and `ataegina env --no-export > .env` writes a
# sourceable file. Values are single-quoted so paths with spaces/quotes survive a
# round-trip. No servers, no network — purely derived from the registry + config.
#
# Hermetic: ATE_PORT_TOOL=none, temp registry, LOG_DIR_BASE under $ATE_TMP. Default
# port bases are FRONT_PORT_BASE=5173, BACK_PORT_BASE=8000, so index 0 -> 5173/8000
# and index 1 -> 5174/8001.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  DBCFG=(
    "DB_NAME=myapp"
    "DB_KIND=custom"
    "DB_SUFFIX=_wt"
    "DB_URL_VAR=DATABASE_URL"
    "DB_URL_TEMPLATE='postgres://localhost:5432/\$ATE_DB_NAME'"
    "DB_AUTO_CREATE=0"
  )
}
teardown() { common_teardown; }

@test "env prints eval-able export lines for the primary (index 0)" {
  cd "$REPO"
  run ate env
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^export ATE_INDEX='0'$"
  echo "$output" | grep -q "^export FRONTEND_PORT='5173'$"
  echo "$output" | grep -q "^export BACKEND_PORT='8000'$"
  echo "$output" | grep -q "^export FRONTEND_URL='http://localhost:5173'$"
  echo "$output" | grep -q "^export BACKEND_URL='http://localhost:8000'$"
  echo "$output" | grep -q "^export FRONTEND_API_BASE_URL='http://localhost:8000'$"
}

@test "env reflects a linked worktree's own derived ports (index 1)" {
  wt="$(add_worktree "$REPO" wtA)"
  cd "$wt"
  run ate env
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^export ATE_INDEX='1'$"
  echo "$output" | grep -q "^export FRONTEND_PORT='5174'$"
  echo "$output" | grep -q "^export BACKEND_PORT='8001'$"
}

@test "eval \"\$(ate env)\" sets the derived variables in the caller's shell" {
  cd "$REPO"
  run ate env
  [ "$status" -eq 0 ]
  # Evaluate the emitted assignments in a clean subshell and read them back.
  FRONTEND_PORT="" BACKEND_PORT="" ATE_INDEX=""
  eval "$output"
  [ "$ATE_INDEX" = "0" ]
  [ "$FRONTEND_PORT" = "5173" ]
  [ "$BACKEND_PORT" = "8000" ]
}

@test "env --no-export drops the 'export ' prefix (sourceable .env form)" {
  cd "$REPO"
  run ate env --no-export
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^FRONTEND_PORT='5173'$"
  echo "$output" | grep -q "^BACKEND_PORT='8000'$"
  # No line should carry the export keyword.
  refute_output_has "export "
}

@test "env includes the per-worktree DB name and URL when a DB is configured" {
  write_config "$REPO" "${DBCFG[@]}"
  wt="$(add_worktree "$REPO" wtA)"
  write_config "$wt" "${DBCFG[@]}"
  cd "$wt"
  run ate env
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^export ATE_DB_NAME='myapp_wt1'$"
  echo "$output" | grep -q "^export DATABASE_URL='postgres://localhost:5432/myapp_wt1'$"
}

@test "env omits DB variables when no database is configured" {
  cd "$REPO"
  run ate env
  [ "$status" -eq 0 ]
  refute_output_has "ATE_DB_NAME"
  refute_output_has "DATABASE_URL"
}

@test "env honors a custom DB_URL_VAR name" {
  local cfg=(
    "DB_NAME=myapp"
    "DB_KIND=custom"
    "DB_SUFFIX=_wt"
    "DB_URL_VAR=MY_DB_DSN"
    "DB_URL_TEMPLATE='postgres://localhost:5432/\$ATE_DB_NAME'"
    "DB_AUTO_CREATE=0"
  )
  write_config "$REPO" "${cfg[@]}"
  cd "$REPO"
  run ate env
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^export MY_DB_DSN='postgres://localhost:5432/myapp'$"
  refute_output_has "DATABASE_URL"
}

@test "env single-quotes values so a repo path with spaces round-trips" {
  spaced="$ATE_TMP/my repo dir"
  local repo; repo="$(make_repo "$spaced")"
  cd "$repo"
  run ate env
  [ "$status" -eq 0 ]
  REPO_ROOT=""
  eval "$output"
  [ "$REPO_ROOT" = "$spaced" ]
}

@test "env's ports agree with what 'ports' reports" {
  wt="$(add_worktree "$REPO" wtA)"
  cd "$wt"
  run ate ports
  echo "$output" | grep -q "http://localhost:5174"   # frontend
  echo "$output" | grep -q "http://localhost:8001"   # backend
  run ate env
  echo "$output" | grep -q "^export FRONTEND_PORT='5174'$"
  echo "$output" | grep -q "^export BACKEND_PORT='8001'$"
}

@test "env with an unknown option exits 2" {
  cd "$REPO"
  run ate env --bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "unknown option"
}

@test "env outside a git worktree errors clearly" {
  cd "$ATE_TMP"
  run ate env
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not inside a git worktree"
}
