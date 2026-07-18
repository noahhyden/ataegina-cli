#!/usr/bin/env bats
# Real `move`: relocating a RUNNING worktree must free its old slot's servers (not
# leave them orphaned on the old ports), then the new slot must come up. Before the
# fix, `move` told you to run `down` to free the old ports — but `down` resolves the
# NEW index after the move and never reached the old servers, leaking them.

load helper

SRV="move_srv_9c2.py"

setup() {
  common_setup
  integration_only
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  if command -v lsof >/dev/null 2>&1; then export ATE_PORT_TOOL=lsof
  elif command -v ss >/dev/null 2>&1; then export ATE_PORT_TOOL=ss
  else skip "no port tool"; fi
}
teardown() {
  pkill -f "$SRV" 2>/dev/null || true
  if command -v lsof >/dev/null 2>&1; then
    for p in 47001 47005; do lsof -ti tcp:$p 2>/dev/null | xargs -r kill -9 2>/dev/null || true; done
  fi
  common_teardown
}

listening() {
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:"$1" >/dev/null 2>&1
  else ss -ltn "sport = :$1" 2>/dev/null | grep -q ":$1"; fi
}
wait_listening() { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" && return 0; sleep 0.25; i=$((i+1)); done; return 1; }
wait_free()      { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" || return 0; sleep 0.25; i=$((i+1)); done; return 1; }

@test "move frees the running old slot, then the new slot comes up" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  cat > "$repo/$SRV" <<'PY'
import os, socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(os.environ["BACKEND_PORT"]))); s.listen(16)
while True: time.sleep(1)
PY
  write_config "$repo" "FRONT_PORT_BASE=46000" "BACK_PORT_BASE=47000" \
    "BACKEND_DIR='.'" "BACKEND_CMD='python3 $SRV'"
  cp "$repo/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
  wt="$(add_worktree "$repo" wt)"
  cp "$repo/$SRV" "$wt/$SRV"

  cd "$wt"
  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening 47001          # worktree index 1 -> backend 47001

  # Relocate to index 5. This must FREE the old slot (:47001) itself.
  run ate move 5
  [ "$status" -eq 0 ]
  wait_free 47001               # old server reaped by the move (no orphan)

  # The new slot then comes up on its derived port.
  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening 47005          # index 5 -> backend 47005

  ate down backend || true
  wait_free 47005
}
