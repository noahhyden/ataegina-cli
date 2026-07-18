#!/usr/bin/env bats
# Real per-worktree MySQL deconfliction against a live server, driven through
# ataegina's own `db create` / `db drop`. Integration test: needs docker, skips
# cleanly otherwise. DB commands go through `docker exec` (a real mysql:8 engine).

load helper

MY_CONTAINER="ate_bats_mysql"
MY_PW="rootpw"

myq() { docker exec "$MY_CONTAINER" mysql -uroot -p"$MY_PW" -N -B -e "$1" 2>/dev/null; }
db_exists() { myq "SELECT schema_name FROM information_schema.schemata WHERE schema_name='$1'"; }
# Real readiness: mysqladmin ping answers BEFORE the server accepts authenticated
# DDL, so probe with an actual query. An env that never gets here -> tests SKIP
# (never false-fail).
my_ready() { docker exec "$MY_CONTAINER" mysql -uroot -p"$MY_PW" -N -B -e "SELECT 1" >/dev/null 2>&1; }

setup_file() {
  [ "${ATE_TEST_DOCKER:-0}" = "1" ] || return 0
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || return 0
  docker rm -f "$MY_CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$MY_CONTAINER" -e MYSQL_ROOT_PASSWORD="$MY_PW" \
    mysql:8 >/dev/null 2>&1 || return 0
  local i
  for i in $(seq 1 120); do my_ready && break; sleep 1; done
}
teardown_file() { docker rm -f "$MY_CONTAINER" >/dev/null 2>&1 || true; }

setup() {
  common_setup
  docker_only
  my_ready || skip "docker/mysql not available"
  myq "DROP DATABASE IF EXISTS shopdb; DROP DATABASE IF EXISTS shopdb_wt1; CREATE DATABASE shopdb" >/dev/null 2>&1 || true
}
teardown() { common_teardown; }

my_config() {
  local repo="$1"
  cat > "$repo/ataegina.config.sh" <<EOF
DB_NAME=shopdb
DB_KIND=mysql
DB_SUFFIX=_wt
DB_URL_TEMPLATE='mysql://root@db/\$ATE_DB_NAME'
DB_CREATE_CMD='docker exec $MY_CONTAINER mysql -uroot -p$MY_PW -e "CREATE DATABASE IF NOT EXISTS \$ATE_DB_NAME"'
DB_DROP_CMD='docker exec $MY_CONTAINER mysql -uroot -p$MY_PW -e "DROP DATABASE IF EXISTS \$ATE_DB_NAME"'
EOF
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
}

@test "mysql: worktree db create makes a real, separate database" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  my_config "$repo"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"
  run ate db name; [ "$output" = "shopdb_wt1" ]
  run ate db create; [ "$status" -eq 0 ]
  [ "$(db_exists shopdb_wt1)" = "shopdb_wt1" ]
}

@test "mysql: each worktree DB holds its own data (real isolation)" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  my_config "$repo"
  wt="$(add_worktree "$repo" wt)"
  ( cd "$wt" && ate db create >/dev/null 2>&1 )
  myq "CREATE TABLE shopdb.t(x INT); INSERT INTO shopdb.t VALUES (100)" >/dev/null
  myq "CREATE TABLE shopdb_wt1.t(x INT); INSERT INTO shopdb_wt1.t VALUES (999)" >/dev/null
  [ "$(myq 'SELECT x FROM shopdb.t')" = "100" ]
  [ "$(myq 'SELECT x FROM shopdb_wt1.t')" = "999" ]
}

@test "mysql: worktree db drop removes only the worktree DB; primary refused" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  my_config "$repo"
  wt="$(add_worktree "$repo" wt)"
  ( cd "$wt" && ate db create >/dev/null 2>&1 )
  cd "$wt"
  run ate db drop; [ "$status" -eq 0 ]
  [ -z "$(db_exists shopdb_wt1)" ]
  cd "$repo"
  run ate db drop; [ "$status" -ne 0 ]
  [ "$(db_exists shopdb)" = "shopdb" ]
}
