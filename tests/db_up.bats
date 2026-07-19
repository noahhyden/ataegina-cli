#!/usr/bin/env bats
# `up`'s per-worktree DB auto-create path (ate_db_ensure), driven HERMETICALLY via a
# fake DB CLI (tests/fake/mockdb.sh) — no engine, no docker, no network. This covers
# what db_up_autocreate.bats (docker-gated) and db.bats (drives `db create` directly)
# do not: the NON-FATAL guarantee (a failing DB engine must NOT block the dev stack)
# and the primary-skip. The backend is a trivial `true` so only the DB path matters;
# ATE_PORT_TOOL=none (helper default) keeps it fully hermetic.

load helper

MOCKDB="$BATS_TEST_DIRNAME/fake/mockdb.sh"

setup() {
  common_setup
  LOG="$ATE_TMP/db-calls.log"
}
teardown() { common_teardown; }

# Write a DB-enabled config whose create/drop hooks are the fake CLI. $2 is the exit
# code the fake `create` returns (0 = healthy engine, 1 = broken/unavailable engine).
dbcfg() {
  local dir="$1" create_exit="$2"
  write_config "$dir" \
    "DB_NAME=myapp" "DB_KIND=custom" "DB_SUFFIX=_wt" "DB_AUTO_CREATE=1" \
    "BACKEND_DIR='.'" "BACKEND_CMD='true'" \
    "DB_CREATE_CMD='bash \"$MOCKDB\" create \"$LOG\" $create_exit'" \
    "DB_DROP_CMD='bash \"$MOCKDB\" drop \"$LOG\" 0'"
}

@test "up auto-creates the per-worktree DB (with the derived name) before the backend" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"; dbcfg "$repo" 0
  wt="$(add_worktree "$repo" wtA)"; dbcfg "$wt" 0
  cd "$wt"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  grep -q "^create myapp_wt1$" "$LOG"     # index 1 -> myapp_wt1
  echo "$output" | grep -qi "db ready"
}

@test "up is NON-FATAL when the DB create fails (a dead engine must not block the stack)" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"; dbcfg "$repo" 1
  wt="$(add_worktree "$repo" wtA)"; dbcfg "$wt" 1
  cd "$wt"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]                      # up must NOT fail because the DB engine did
  grep -q "^create myapp_wt1$" "$LOG"      # the create WAS attempted
  echo "$output" | grep -qi "create skipped"   # and reported non-fatally
}

@test "up skips DB create for the primary (index 0 keeps the shared dev DB)" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"; dbcfg "$repo" 0
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  # ate_db_ensure returns early for the primary: no create hook, no "db ready".
  [ ! -f "$LOG" ] || refute grep -q "^create myapp$" "$LOG"
  refute_output_has "db ready"
}

@test "up does not auto-create when DB_AUTO_CREATE=0" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wtA)"
  write_config "$wt" \
    "DB_NAME=myapp" "DB_KIND=custom" "DB_SUFFIX=_wt" "DB_AUTO_CREATE=0" \
    "BACKEND_DIR='.'" "BACKEND_CMD='true'" \
    "DB_CREATE_CMD='bash \"$MOCKDB\" create \"$LOG\" 0'"
  cd "$wt"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ] || refute grep -q "^create" "$LOG"
}
