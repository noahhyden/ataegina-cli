#!/usr/bin/env bats
# The whole promise, end to end, with REAL everything: two worktrees each run a real
# backend process, on DISTINCT derived ports, SIMULTANEOUSLY, each connected to its
# OWN per-worktree database (a real sqlite engine via python stdlib) — no port
# collision, no shared DB. This is the collision-free guarantee the tool exists for,
# exercised as a user would hit it, not asserted piecemeal.

load helper

SRV="flagship_srv.py"   # unique name so teardown can reap precisely

setup() {
  common_setup
  integration_only
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  command -v sqlite3 >/dev/null 2>&1 || skip "sqlite3 required"
  if command -v lsof >/dev/null 2>&1; then export ATE_PORT_TOOL=lsof
  elif command -v ss >/dev/null 2>&1; then export ATE_PORT_TOOL=ss
  else skip "no port tool"; fi
}
teardown() {
  pkill -f "$SRV" 2>/dev/null || true
  common_teardown
}

listening() {
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:"$1" >/dev/null 2>&1
  else ss -ltn "sport = :$1" 2>/dev/null | grep -q ":$1"; fi
}
wait_listening() { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" && return 0; sleep 0.25; i=$((i+1)); done; return 1; }
wait_free()      { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" || return 0; sleep 0.25; i=$((i+1)); done; return 1; }

@test "two worktrees: distinct ports + own DBs, running at the same time" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  mkdir -p "$ATE_TMP/data"

  # Backend: connect to its injected DATABASE_URL (sqlite), record its index+port,
  # then hold the port. Proves both the DB wiring and the process/port lifecycle.
  cat > "$repo/$SRV" <<'PY'
import os, sqlite3, socket, time
path = os.environ.get("DATABASE_URL", "").replace("sqlite:///", "")
con = sqlite3.connect(path)
con.execute("CREATE TABLE IF NOT EXISTS boot(idx INT, port INT)")
con.execute("INSERT INTO boot VALUES (?,?)",
            (int(os.environ.get("ATE_INDEX", "-1")), int(os.environ.get("BACKEND_PORT", "0"))))
con.commit(); con.close()
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(os.environ["BACKEND_PORT"]))); s.listen(16)
while True: time.sleep(1)
PY

  write_config "$repo" \
    "FRONT_PORT_BASE=49000" "BACK_PORT_BASE=48000" \
    "BACKEND_DIR='.'" "BACKEND_CMD='python3 $SRV'" \
    "DB_NAME=$ATE_TMP/data/app" "DB_KIND=sqlite" "DB_SUFFIX=_wt" \
    "DB_URL_TEMPLATE='sqlite:///\$ATE_DB_NAME.db'"
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"

  wt="$(add_worktree "$repo" wt)"
  cp "$repo/$SRV" "$wt/$SRV"   # untracked file isn't carried into the worktree

  # Bring BOTH up (backend only), then assert both are listening at once.
  cd "$repo"
  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  cd "$wt"
  run ate up backend --scope backend
  [ "$status" -eq 0 ]

  wait_listening 48000    # primary index 0
  wait_listening 48001    # worktree index 1
  # Both alive simultaneously == no port collision.
  listening 48000
  listening 48001

  # Own DBs: primary -> app.db (index 0), worktree -> app_wt1.db (index 1).
  [ -f "$ATE_TMP/data/app.db" ]
  [ -f "$ATE_TMP/data/app_wt1.db" ]
  run sqlite3 "$ATE_TMP/data/app.db" "SELECT idx||':'||port FROM boot"
  [ "$output" = "0:48000" ]
  run sqlite3 "$ATE_TMP/data/app_wt1.db" "SELECT idx||':'||port FROM boot"
  [ "$output" = "1:48001" ]

  # Tear both down; both ports freed.
  cd "$repo"; ate down backend || true
  cd "$wt";   ate down backend || true
  wait_free 48000
  wait_free 48001
}
