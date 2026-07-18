#!/usr/bin/env bats
# Real up/down with a Go backend. `go run .` is a compile-then-exec tree — a `go`
# parent plus the compiled binary (a grandchild of the launch wrapper) that actually
# holds the port — so this also exercises the whole-tree teardown against a real
# multi-level process, with a different runtime than python/node.

load helper

MOD="ate_go_e2e_mod"

setup() {
  common_setup
  integration_only
  command -v go >/dev/null 2>&1 || skip "go required"
  if command -v lsof >/dev/null 2>&1; then export ATE_PORT_TOOL=lsof
  elif command -v ss >/dev/null 2>&1; then export ATE_PORT_TOOL=ss
  else skip "no port tool"; fi
}
teardown() {
  pkill -f "$MOD" 2>/dev/null || true          # compiled binary
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti tcp:47000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
  fi
  common_teardown
}

listening() {
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:"$1" >/dev/null 2>&1
  else ss -ltn "sport = :$1" 2>/dev/null | grep -q ":$1"; fi
}
# Go's first compile can take several seconds; be generous.
wait_listening() { local p="$1" i=0; while [ "$i" -lt 80 ]; do listening "$p" && return 0; sleep 0.5; i=$((i+1)); done; return 1; }
wait_free()      { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" || return 0; sleep 0.5; i=$((i+1)); done; return 1; }

@test "real up/down: go backend binds the derived port; down reaps the compile-exec tree" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  cat > "$repo/main.go" <<'GO'
package main
import ("net";"os";"time")
func main() {
	ln, err := net.Listen("tcp", "127.0.0.1:"+os.Getenv("BACKEND_PORT"))
	if err != nil { panic(err) }
	defer ln.Close()
	for { time.Sleep(time.Second) }
}
GO
  ( cd "$repo" && go mod init "$MOD" >/dev/null 2>&1 )
  write_config "$repo" "FRONT_PORT_BASE=46000" "BACK_PORT_BASE=47000" \
    "BACKEND_DIR='.'" "BACKEND_CMD='go run .'"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening 47000          # primary index 0 -> 47000; real go server bound it

  ate down backend
  wait_free 47000               # compiled binary (grandchild of the wrapper) reaped
  # The compiled binary must be gone (tree reap reached the grandchild).
  run pgrep -f "$MOD"
  [ -z "$output" ]
}
