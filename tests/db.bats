#!/usr/bin/env bats
# Per-worktree database deconfliction (the new feature).
#
# No real database engine is touched: DB_CREATE_CMD / DB_DROP_CMD are stubbed to
# append a line to a temp file, so we can assert they ran with the right
# ATE_DB_NAME without installing postgres/mysql.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  MARK="$ATE_TMP/db-calls.log"
  # DB_KIND=custom so no per-kind default CLI is assumed; the stub commands write
  # to $MARK. They reference $ATE_DB_NAME, which ataegina exports per worktree.
  DBCFG=(
    "DB_NAME=myapp"
    "DB_KIND=custom"
    "DB_SUFFIX=_wt"
    "DB_URL_VAR=DATABASE_URL"
    "DB_URL_TEMPLATE='postgres://localhost:5432/\$ATE_DB_NAME'"
    "DB_AUTO_CREATE=0"
    "DB_CREATE_CMD='echo create \$ATE_DB_NAME >> $MARK'"
    "DB_DROP_CMD='echo drop \$ATE_DB_NAME >> $MARK'"
  )
}
teardown() { common_teardown; }

@test "primary db name is the unsuffixed DB_NAME" {
  write_config "$REPO" "${DBCFG[@]}"
  cd "$REPO"
  run ate db name
  [ "$status" -eq 0 ]
  [ "$output" = "myapp" ]
}

@test "worktree #1 db name is DB_NAME + suffix + index" {
  write_config "$REPO" "${DBCFG[@]}"
  wt="$(add_worktree "$REPO" wtA)"
  write_config "$wt" "${DBCFG[@]}"
  cd "$wt"
  run ate db name
  [ "$status" -eq 0 ]
  [ "$output" = "myapp_wt1" ]
}

@test "db url expands DB_URL_TEMPLATE with the per-worktree db name" {
  write_config "$REPO" "${DBCFG[@]}"
  wt="$(add_worktree "$REPO" wtA)"
  write_config "$wt" "${DBCFG[@]}"
  cd "$wt"
  run ate db url
  [ "$status" -eq 0 ]
  [ "$output" = "postgres://localhost:5432/myapp_wt1" ]
}

@test "db create invokes DB_CREATE_CMD with the worktree db name" {
  write_config "$REPO" "${DBCFG[@]}"
  wt="$(add_worktree "$REPO" wtA)"
  write_config "$wt" "${DBCFG[@]}"
  cd "$wt"
  run ate db create
  [ "$status" -eq 0 ]
  grep -q "^create myapp_wt1$" "$MARK"
}

@test "db drop invokes DB_DROP_CMD with the worktree db name" {
  write_config "$REPO" "${DBCFG[@]}"
  wt="$(add_worktree "$REPO" wtA)"
  write_config "$wt" "${DBCFG[@]}"
  cd "$wt"
  run ate db drop
  [ "$status" -eq 0 ]
  grep -q "^drop myapp_wt1$" "$MARK"
}

@test "db drop on the PRIMARY is refused (nonzero, never invokes the drop cmd)" {
  write_config "$REPO" "${DBCFG[@]}"
  cd "$REPO"
  run ate db drop
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "refusing to drop the PRIMARY"
  # The drop command must NOT have run.
  [ ! -f "$MARK" ] || ! grep -q "^drop myapp$" "$MARK"
}

@test "db commands error out when DB_NAME is not configured" {
  # No DB config at all.
  write_config "$REPO" "FRONT_PORT_BASE=5173"
  cd "$REPO"
  run ate db name
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "no database configured"
}
