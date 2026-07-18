#!/usr/bin/env bats
# Real `up` with the default `both` scope: frontend AND backend come up together on
# distinct derived ports. Plus idempotency: re-running `up` must NOT start a second
# copy — the already-listening server is detected and left as-is (same pid).

load helper

FEMARK="ate_both_fe_3d7.py"
BEMARK="ate_both_be_3d7.py"

setup() {
  common_setup
  integration_only
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  if command -v lsof >/dev/null 2>&1; then export ATE_PORT_TOOL=lsof
  elif command -v ss >/dev/null 2>&1; then export ATE_PORT_TOOL=ss
  else skip "no port tool"; fi
}
teardown() {
  pkill -f "$FEMARK" 2>/dev/null || true
  pkill -f "$BEMARK" 2>/dev/null || true
  if command -v lsof >/dev/null 2>&1; then
    for p in 46000 47000; do lsof -ti tcp:$p 2>/dev/null | xargs -r kill -9 2>/dev/null || true; done
  fi
  common_teardown
}

listening() {
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:"$1" >/dev/null 2>&1
  else ss -ltn "sport = :$1" 2>/dev/null | grep -q ":$1"; fi
}
holder() { lsof -ti tcp:"$1" 2>/dev/null | head -n1; }
wait_listening() { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" && return 0; sleep 0.25; i=$((i+1)); done; return 1; }
wait_free()      { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" || return 0; sleep 0.25; i=$((i+1)); done; return 1; }

@test "up both starts frontend + backend on distinct ports; re-up is idempotent" {
  command -v lsof >/dev/null 2>&1 || skip "needs lsof to compare pids"
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  for f in "$FEMARK" "$BEMARK"; do
    cat > "$repo/$f" <<PY
import os, socket, time  # $f
port = int(os.environ.get("FRONTEND_PORT") if "$f" == "$FEMARK" else os.environ.get("BACKEND_PORT"))
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port)); s.listen(16)
while True: time.sleep(1)
PY
  done
  write_config "$repo" "FRONT_PORT_BASE=46000" "BACK_PORT_BASE=47000" \
    "FRONTEND_DIR='.'" "FRONTEND_CMD='python3 $FEMARK'" \
    "BACKEND_DIR='.'"  "BACKEND_CMD='python3 $BEMARK'"
  cd "$repo"

  run ate up both
  [ "$status" -eq 0 ]
  wait_listening 46000     # primary index 0 -> frontend 46000
  wait_listening 47000     # primary index 0 -> backend 47000
  local fe1 be1
  fe1="$(holder 46000)"; be1="$(holder 47000)"
  [ -n "$fe1" ] && [ -n "$be1" ]

  # Re-run up: must be idempotent — same pids still hold the ports (no second copy).
  run ate up both
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already up"
  [ "$(holder 46000)" = "$fe1" ]
  [ "$(holder 47000)" = "$be1" ]

  ate down both || true
  wait_free 46000
  wait_free 47000
}
