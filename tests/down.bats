#!/usr/bin/env bats
# `down` pidfile teardown: a launched-but-unbound process is killed via the
# recorded pidfile, and the pidfile removed. Plus the "nothing to stop" path.
#
# With ATE_PORT_TOOL=none, port probing reports nothing listening, so the ONLY
# way `down` can stop a server is via the pidfile recorded at `up`. A `sleep 60`
# backend never binds a port, exercising exactly that pidfile path.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  # Backend that launches but never binds a port. Frontend left unset.
  write_config "$REPO" \
    "FRONT_PORT_BASE=5173" "BACK_PORT_BASE=8000" \
    "BACKEND_DIR=." "BACKEND_CMD='sleep 60'"
}
teardown() {
  # Make sure no stray sleep survives a failing assertion.
  [ -n "${LAUNCHED_PID:-}" ] && kill "$LAUNCHED_PID" 2>/dev/null
  common_teardown
}

@test "down kills a launched-but-unbound backend via its pidfile and removes the pidfile" {
  cd "$REPO"
  # `up backend` launches the server (we assert on the pidfile, not its exit
  # code: with no frontend the final readiness short-circuit makes `up backend`
  # return nonzero, which is existing behavior unrelated to teardown).
  run ate up backend

  pidfile="$ATE_TMP/logs/ate-wt0/backend.pid"
  [ -f "$pidfile" ]
  LAUNCHED_PID="$(cat "$pidfile")"
  [ -n "$LAUNCHED_PID" ]
  # The launched process is alive.
  kill -0 "$LAUNCHED_PID"

  run ate down backend
  [ "$status" -eq 0 ]
  # A successful stop reports what it stopped (not silent).
  echo "$output" | grep -qi "stopped"

  # Pidfile removed.
  [ ! -f "$pidfile" ]
  # Give the kill a moment to land, then confirm the process is gone.
  i=0
  while [ "$i" -lt 20 ] && kill -0 "$LAUNCHED_PID" 2>/dev/null; do
    sleep 0.1; i=$((i + 1))
  done
  refute_alive "$LAUNCHED_PID"
}

@test "down with nothing running reports nothing to stop (no error)" {
  cd "$REPO"
  # No `up` was run, so there is no pidfile and (port tool none) nothing on port.
  run ate down backend
  # _ate_stop_port prints to stderr; run merges it into $output.
  echo "$output" | grep -qi "nothing to stop"
}
