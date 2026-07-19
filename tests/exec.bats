#!/usr/bin/env bats
# `ataegina exec [--] CMD [args...]` — run CMD with this worktree's derived
# environment injected (the same variables `up` gives your servers and `env`
# prints), inheriting stdio and the current directory, exiting with CMD's status.
#
# Spec: this is the one-shot complement to `eval "$(ataegina env)"` — it runs a
# command with ATE_INDEX / FRONTEND_PORT / BACKEND_PORT / the URLs / DEV_LOG_DIR
# (and ATE_DB_NAME + the DB URL when configured) exported, without touching your
# shell. An optional `--` separates ataegina's args from the command. No command
# is an error (exit 2). Hermetic: derives from the registry + config, no network.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
}
teardown() { common_teardown; }

@test "exec injects the derived FRONTEND_PORT into the command (primary)" {
  cd "$REPO"
  run ate exec -- sh -c 'echo "port=$FRONTEND_PORT"'
  [ "$status" -eq 0 ]
  [ "$output" = "port=5173" ]
}

@test "exec injects a linked worktree's own derived ports (index 1)" {
  wt="$(add_worktree "$REPO" wtA)"
  cd "$wt"
  run ate exec -- sh -c 'echo "$ATE_INDEX $FRONTEND_PORT $BACKEND_PORT"'
  [ "$status" -eq 0 ]
  [ "$output" = "1 5174 8001" ]
}

@test "exec injects the per-worktree DATABASE_URL when a DB is configured" {
  local cfg=(
    "DB_NAME=myapp"
    "DB_KIND=custom"
    "DB_SUFFIX=_wt"
    "DB_URL_VAR=DATABASE_URL"
    "DB_URL_TEMPLATE='postgres://localhost:5432/\$ATE_DB_NAME'"
    "DB_AUTO_CREATE=0"
  )
  write_config "$REPO" "${cfg[@]}"
  wt="$(add_worktree "$REPO" wtA)"
  write_config "$wt" "${cfg[@]}"
  cd "$wt"
  run ate exec -- sh -c 'echo "$DATABASE_URL"'
  [ "$status" -eq 0 ]
  [ "$output" = "postgres://localhost:5432/myapp_wt1" ]
}

@test "exec propagates the command's exit status" {
  cd "$REPO"
  run ate exec -- sh -c 'exit 3'
  [ "$status" -eq 3 ]
}

@test "exec passes arguments through verbatim (including leading-dash args)" {
  cd "$REPO"
  run ate exec -- printf '%s|%s' -n hello
  [ "$status" -eq 0 ]
  [ "$output" = "-n|hello" ]
}

@test "exec works without the -- separator" {
  cd "$REPO"
  run ate exec sh -c 'echo "$BACKEND_PORT"'
  [ "$status" -eq 0 ]
  [ "$output" = "8000" ]
}

@test "exec protects a command whose name starts with a dash" {
  cd "$REPO"
  # A dash-named command must be treated as a COMMAND (attempted, then
  # not-found = 127), never parsed as an ataegina/exec option (which would fail
  # with an "invalid option" usage error, exit 2). This is why exec emits `--`.
  run ate exec -- -no-such-dash-cmd-xyz
  [ "$status" -eq 127 ]
  refute_output_has "invalid option"
  refute_output_has "needs a command"
}

@test "exec with no command errors (exit 2)" {
  cd "$REPO"
  run ate exec
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "needs a command"
}

@test "exec with only a -- and no command errors (exit 2)" {
  cd "$REPO"
  run ate exec --
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "needs a command"
}

@test "exec runs in the current worktree directory" {
  wt="$(add_worktree "$REPO" wtA)"
  cd "$wt"
  run ate exec -- sh -c 'basename "$PWD"'
  [ "$status" -eq 0 ]
  [ "$output" = "repo-wtA" ]
}

@test "exec outside a git worktree errors clearly" {
  cd "$ATE_TMP"
  run ate exec -- true
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not inside a git worktree"
}
