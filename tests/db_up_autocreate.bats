#!/usr/bin/env bats
# Real integration of `up` with per-worktree DB auto-create: bringing a worktree up
# (DB_AUTO_CREATE=1) must run ate_db_ensure and actually create that worktree's
# database in the live engine BEFORE the backend starts — the flagship "each worktree
# boots against its own DB" behavior, via the `up` path (db_postgres.bats drives
# `db create` directly; this drives `up`). Docker-gated; skips cleanly without docker.

load helper

PG_CONTAINER="ate_bats_pg_up"

setup_file() {
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || return 0
  docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$PG_CONTAINER" -e POSTGRES_PASSWORD=pw -e POSTGRES_USER=ateuser \
    postgres:16-alpine >/dev/null 2>&1 || return 0
  local i
  for i in $(seq 1 30); do
    docker exec "$PG_CONTAINER" pg_isready -U ateuser >/dev/null 2>&1 && break
    sleep 1
  done
}
teardown_file() { docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true; }

pg_ready() { docker exec "$PG_CONTAINER" pg_isready -U ateuser >/dev/null 2>&1; }
pgq() { docker exec "$PG_CONTAINER" psql -U ateuser -tAqc "$1" 2>/dev/null; }

setup() {
  common_setup
  pg_ready || skip "docker/postgres not available"
  if command -v lsof >/dev/null 2>&1; then export ATE_PORT_TOOL=lsof
  elif command -v ss >/dev/null 2>&1; then export ATE_PORT_TOOL=ss
  else skip "no port tool"; fi
  docker exec "$PG_CONTAINER" dropdb -U ateuser --if-exists shopdb    >/dev/null 2>&1 || true
  docker exec "$PG_CONTAINER" dropdb -U ateuser --if-exists shopdb_wt1 >/dev/null 2>&1 || true
  docker exec "$PG_CONTAINER" createdb -U ateuser shopdb >/dev/null 2>&1 || true
}
teardown() {
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:47000 2>/dev/null | xargs -r kill -9 2>/dev/null || true; fi
  common_teardown
}

listening() {
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:"$1" >/dev/null 2>&1
  else ss -ltn "sport = :$1" 2>/dev/null | grep -q ":$1"; fi
}
wait_listening() { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" && return 0; sleep 0.25; i=$((i+1)); done; return 1; }

@test "up on a worktree auto-creates its database in the live engine, then starts the backend" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  # A real backend that just holds its port; the DB is created by ate_db_ensure at `up`.
  cat > "$repo/beserver.py" <<'PY'
import os, socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(os.environ["BACKEND_PORT"]))); s.listen(16)
while True: time.sleep(1)
PY
  cat > "$repo/ataegina.config.sh" <<EOF
FRONT_PORT_BASE=46000
BACK_PORT_BASE=47000
BACKEND_DIR='.'
BACKEND_CMD='python3 beserver.py'
DB_NAME=shopdb
DB_KIND=postgres
DB_SUFFIX=_wt
DB_AUTO_CREATE=1
DB_URL_TEMPLATE='postgres://ateuser@db/\$ATE_DB_NAME'
DB_CREATE_CMD='docker exec $PG_CONTAINER createdb -U ateuser "\$ATE_DB_NAME"'
DB_DROP_CMD='docker exec $PG_CONTAINER dropdb -U ateuser --if-exists "\$ATE_DB_NAME"'
EOF
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
  wt="$(add_worktree "$repo" wt)"
  cp "$repo/beserver.py" "$wt/beserver.py"

  # Precondition: the worktree DB does NOT exist yet.
  [ -z "$(pgq "SELECT datname FROM pg_database WHERE datname='shopdb_wt1'")" ]

  cd "$wt"
  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening 47001    # worktree index 1 -> backend 47001

  # `up` created the worktree's database in the live engine.
  [ "$(pgq "SELECT datname FROM pg_database WHERE datname='shopdb_wt1'")" = "shopdb_wt1" ]

  ate down backend || true
}
