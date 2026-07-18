#!/usr/bin/env bats
# Real per-worktree postgres deconfliction against a live server, driven through
# ataegina's own `db create` / `db drop`. Integration test: it needs docker and
# skips cleanly when docker (or the container) is unavailable, so the rest of the
# suite stays hermetic. The DB commands go through `docker exec` (a real postgres
# engine) because this host's published-port path to the container is unreliable.

load helper

PG_CONTAINER="ate_bats_pg"

# Start ONE throwaway postgres for the whole file; remove it after.
setup_file() {
  [ "${ATE_TEST_DOCKER:-0}" = "1" ] || return 0
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || return 0
  docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$PG_CONTAINER" \
    -e POSTGRES_PASSWORD=pw -e POSTGRES_USER=ateuser \
    postgres:16-alpine >/dev/null 2>&1 || return 0
  local i
  for i in $(seq 1 30); do
    docker exec "$PG_CONTAINER" pg_isready -U ateuser >/dev/null 2>&1 && break
    sleep 1
  done
}

teardown_file() {
  docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
}

setup() {
  common_setup
  docker_only
  docker exec "$PG_CONTAINER" pg_isready -U ateuser >/dev/null 2>&1 \
    || skip "docker/postgres not available"
  # Fresh base state for each test.
  docker exec "$PG_CONTAINER" dropdb -U ateuser --if-exists shopdb    >/dev/null 2>&1 || true
  docker exec "$PG_CONTAINER" dropdb -U ateuser --if-exists shopdb_wt1 >/dev/null 2>&1 || true
  docker exec "$PG_CONTAINER" createdb -U ateuser shopdb >/dev/null 2>&1 || true
}
teardown() { common_teardown; }

# Write a postgres config whose create/drop go through docker exec into the live pg.
pg_config() {
  local repo="$1"
  write_config "$repo" \
    "DB_NAME=shopdb" "DB_KIND=postgres" "DB_SUFFIX=_wt" \
    "DB_URL_TEMPLATE='postgres://ateuser@db/\$ATE_DB_NAME'" \
    "DB_CREATE_CMD='docker exec $PG_CONTAINER createdb -U ateuser \"\$ATE_DB_NAME\"'" \
    "DB_DROP_CMD='docker exec $PG_CONTAINER dropdb -U ateuser --if-exists \"\$ATE_DB_NAME\"'"
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
}

@test "postgres: worktree db create makes a real, separate database" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  pg_config "$repo"
  wt="$(add_worktree "$repo" wt)"

  cd "$wt"
  run ate db name
  [ "$output" = "shopdb_wt1" ]

  run ate db create
  [ "$status" -eq 0 ]
  # The database really exists in postgres now.
  run docker exec "$PG_CONTAINER" psql -U ateuser -tAqc \
    "select datname from pg_database where datname='shopdb_wt1'"
  [ "$output" = "shopdb_wt1" ]
}

@test "postgres: each worktree DB holds its own data (real isolation)" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  pg_config "$repo"
  wt="$(add_worktree "$repo" wt)"
  ( cd "$wt" && ate db create >/dev/null 2>&1 )

  docker exec "$PG_CONTAINER" psql -U ateuser -d shopdb     -tAqc \
    "create table t(x int); insert into t values (100)" >/dev/null
  docker exec "$PG_CONTAINER" psql -U ateuser -d shopdb_wt1 -tAqc \
    "create table t(x int); insert into t values (999)" >/dev/null

  run docker exec "$PG_CONTAINER" psql -U ateuser -d shopdb -tAqc "select x from t"
  [ "$output" = "100" ]
  run docker exec "$PG_CONTAINER" psql -U ateuser -d shopdb_wt1 -tAqc "select x from t"
  [ "$output" = "999" ]
}

@test "postgres: worktree db drop removes only the worktree DB; primary is refused" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  pg_config "$repo"
  wt="$(add_worktree "$repo" wt)"
  ( cd "$wt" && ate db create >/dev/null 2>&1 )

  cd "$wt"
  run ate db drop
  [ "$status" -eq 0 ]
  run docker exec "$PG_CONTAINER" psql -U ateuser -tAqc \
    "select datname from pg_database where datname='shopdb_wt1'"
  [ -z "$output" ]

  # Primary drop is refused and the shared DB survives.
  cd "$repo"
  run ate db drop
  [ "$status" -ne 0 ]
  run docker exec "$PG_CONTAINER" psql -U ateuser -tAqc \
    "select datname from pg_database where datname='shopdb'"
  [ "$output" = "shopdb" ]
}
