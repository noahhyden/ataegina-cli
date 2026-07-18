#!/usr/bin/env bats
# Real per-worktree MariaDB deconfliction against a live server, driven through
# ataegina's own `db create` / `db drop` (DB_KIND=mariadb uses the mysql-family
# default commands). Docker-gated + local-only (ATE_TEST_DOCKER=1); skips cleanly
# otherwise. DB ops go through `docker exec` (a real mariadb engine).

load helper

MC="ate_bats_mariadb"
MPW="rootpw"

mdq() { docker exec "$MC" mariadb -uroot -p"$MPW" -N -B -e "$1" 2>/dev/null; }
db_exists() { mdq "SELECT schema_name FROM information_schema.schemata WHERE schema_name='$1'"; }
md_ready() { docker exec "$MC" mariadb -uroot -p"$MPW" -N -B -e "SELECT 1" >/dev/null 2>&1; }

setup_file() {
  [ "${ATE_TEST_DOCKER:-0}" = "1" ] || return 0
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || return 0
  docker rm -f "$MC" >/dev/null 2>&1 || true
  docker run -d --name "$MC" -e MARIADB_ROOT_PASSWORD="$MPW" mariadb:lts >/dev/null 2>&1 || return 0
  local i
  for i in $(seq 1 120); do md_ready && break; sleep 1; done
}
teardown_file() { docker rm -f "$MC" >/dev/null 2>&1 || true; }

setup() {
  common_setup
  docker_only
  md_ready || skip "docker/mariadb not available"
  mdq "DROP DATABASE IF EXISTS shopdb; DROP DATABASE IF EXISTS shopdb_wt1; CREATE DATABASE shopdb" >/dev/null 2>&1 || true
}
teardown() { common_teardown; }

md_config() {
  local repo="$1"
  cat > "$repo/ataegina.config.sh" <<EOF
DB_NAME=shopdb
DB_KIND=mariadb
DB_SUFFIX=_wt
DB_URL_TEMPLATE='mysql://root@db/\$ATE_DB_NAME'
DB_CREATE_CMD='docker exec $MC mariadb -uroot -p$MPW -e "CREATE DATABASE IF NOT EXISTS \$ATE_DB_NAME"'
DB_DROP_CMD='docker exec $MC mariadb -uroot -p$MPW -e "DROP DATABASE IF EXISTS \$ATE_DB_NAME"'
EOF
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
}

@test "mariadb: worktree db create makes a real, separate database" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  md_config "$repo"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"
  run ate db name; [ "$output" = "shopdb_wt1" ]
  run ate db create; [ "$status" -eq 0 ]
  [ "$(db_exists shopdb_wt1)" = "shopdb_wt1" ]
}

@test "mariadb: each worktree DB holds its own data (real isolation)" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  md_config "$repo"
  wt="$(add_worktree "$repo" wt)"
  ( cd "$wt" && ate db create >/dev/null 2>&1 )
  mdq "CREATE TABLE shopdb.t(x INT); INSERT INTO shopdb.t VALUES (100)" >/dev/null
  mdq "CREATE TABLE shopdb_wt1.t(x INT); INSERT INTO shopdb_wt1.t VALUES (999)" >/dev/null
  [ "$(mdq 'SELECT x FROM shopdb.t')" = "100" ]
  [ "$(mdq 'SELECT x FROM shopdb_wt1.t')" = "999" ]
}

@test "mariadb: worktree db drop removes only the worktree DB; primary refused" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  md_config "$repo"
  wt="$(add_worktree "$repo" wt)"
  ( cd "$wt" && ate db create >/dev/null 2>&1 )
  cd "$wt"
  run ate db drop; [ "$status" -eq 0 ]
  [ -z "$(db_exists shopdb_wt1)" ]
  cd "$repo"
  run ate db drop; [ "$status" -ne 0 ]
  [ "$(db_exists shopdb)" = "shopdb" ]
}
