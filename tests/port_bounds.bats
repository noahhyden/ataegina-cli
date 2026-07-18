#!/usr/bin/env bats
# Regression: derived ports are BASE+index and a TCP port must be <= 65535. `move`
# to an oversized index, and `up` at one (e.g. via ATE_INDEX), used to silently
# assign an out-of-range port and let the dev server die on an opaque engine error.
# Both now refuse with a clear message.

load helper

setup()    { common_setup; }
teardown() { common_teardown; }

@test "move refuses an index whose derived port exceeds 65535" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"
  # default BACK_PORT_BASE=8000 -> index 60000 => backend port 68000 (> 65535)
  run ate move 60000
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "65535"
}

@test "move allows an index that stays within range" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"
  run ate move 5
  [ "$status" -eq 0 ]
}

@test "up refuses when the index derives an out-of-range port" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='sleep 5'"
  cd "$repo"
  # ATE_INDEX override pushes backend port to 8000+60000 = 68000
  export ATE_INDEX=60000
  run ate up backend --scope backend
  unset ATE_INDEX
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "65535"
}
