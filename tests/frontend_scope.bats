#!/usr/bin/env bats
# Real scope-aware startup: a frontend-only worktree must start ONLY its frontend and
# point it at the SHARED backend on the base port (served by the primary), not spin up
# its own backend. Exercised with real processes + real port detection + real env
# injection — the borrow-the-shared-backend path the README advertises.

load helper

FESRV="fe_scope_srv.py"
BESRV="be_scope_srv.py"

setup() {
  common_setup
  integration_only
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  if command -v lsof >/dev/null 2>&1; then export ATE_PORT_TOOL=lsof
  elif command -v ss >/dev/null 2>&1; then export ATE_PORT_TOOL=ss
  else skip "no port tool"; fi   # required: up must DETECT the shared backend
}
teardown() {
  pkill -f "$FESRV" 2>/dev/null || true
  pkill -f "$BESRV" 2>/dev/null || true
  common_teardown
}

listening() {
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:"$1" >/dev/null 2>&1
  else ss -ltn "sport = :$1" 2>/dev/null | grep -q ":$1"; fi
}
wait_listening() { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" && return 0; sleep 0.25; i=$((i+1)); done; return 1; }

@test "frontend-only worktree borrows the shared backend, starts no local backend" {
  local repo wt feout
  repo="$(make_repo "$ATE_TMP/repo")"
  feout="$ATE_TMP/fe.out"

  # backend: just hold the port. frontend: record the BACKEND_URL it was handed, hold port.
  cat > "$repo/$BESRV" <<'PY'
import os, socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(os.environ["BACKEND_PORT"]))); s.listen(16)
while True: time.sleep(1)
PY
  cat > "$repo/$FESRV" <<'PY'
import os, socket, time
open(os.environ["FE_OUT"], "w").write("BACKEND_URL=%s\n" % os.environ.get("BACKEND_URL", ""))
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(os.environ["FRONTEND_PORT"]))); s.listen(16)
while True: time.sleep(1)
PY

  write_config "$repo" \
    "FRONT_PORT_BASE=46000" "BACK_PORT_BASE=48000" \
    "BACKEND_DIR='.'"  "BACKEND_CMD='python3 $BESRV'" \
    "FRONTEND_DIR='.'" "FRONTEND_CMD='python3 $FESRV'" \
    "FRONTEND_ENV='FE_OUT=$feout'"
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"

  wt="$(add_worktree "$repo" wt)"
  cp "$repo/$BESRV" "$wt/$BESRV"
  cp "$repo/$FESRV" "$wt/$FESRV"

  # Primary serves the SHARED backend on the base port (48000).
  cd "$repo"
  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening 48000

  # Frontend-only worktree (index 1): should start FE on 46001 and borrow :48000.
  cd "$wt"
  run ate up frontend --scope frontend
  [ "$status" -eq 0 ]
  wait_listening 46001

  # It borrowed the shared backend: the frontend got BACKEND_URL of the BASE port.
  [ -f "$feout" ]
  grep -q "BACKEND_URL=http://localhost:48000" "$feout"
  # And it did NOT start a local backend on the worktree's backend slot (48001).
  refute listening 48001

  cd "$repo"; ate down backend || true
  cd "$wt";   ate down frontend || true
}
