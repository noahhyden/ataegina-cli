#!/usr/bin/env bats
# Real up/down with a Ruby backend — a fourth runtime beyond python/node/go. Confirms
# the launcher is genuinely stack-agnostic: `up` starts `ruby server.rb` on the derived
# port and `down` reaps it.

load helper

MARK="ate_ruby_srv_6b1.rb"

setup() {
  common_setup
  integration_only
  command -v ruby >/dev/null 2>&1 || skip "ruby required"
  if command -v lsof >/dev/null 2>&1; then export ATE_PORT_TOOL=lsof
  elif command -v ss >/dev/null 2>&1; then export ATE_PORT_TOOL=ss
  else skip "no port tool"; fi
}
teardown() {
  pkill -f "$MARK" 2>/dev/null || true
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:47000 2>/dev/null | xargs -r kill -9 2>/dev/null || true; fi
  common_teardown
}

listening() {
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:"$1" >/dev/null 2>&1
  else ss -ltn "sport = :$1" 2>/dev/null | grep -q ":$1"; fi
}
wait_listening() { local p="$1" i=0; while [ "$i" -lt 60 ]; do listening "$p" && return 0; sleep 0.25; i=$((i+1)); done; return 1; }
wait_free()      { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" || return 0; sleep 0.25; i=$((i+1)); done; return 1; }

@test "real up/down: ruby backend binds the derived port, down frees it" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  cat > "$repo/$MARK" <<'RB'
require "socket"
s = TCPServer.new("127.0.0.1", ENV.fetch("BACKEND_PORT").to_i)
loop { sleep 1 }
RB
  write_config "$repo" "FRONT_PORT_BASE=46000" "BACK_PORT_BASE=47000" \
    "BACKEND_DIR='.'" "BACKEND_CMD='ruby $MARK'"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening 47000          # primary index 0 -> backend 47000
  ate down backend
  wait_free 47000
}
