#!/usr/bin/env bats
# Regression: `down` must reap the WHOLE process tree of a launched server, not just
# the port holder + the recorded wrapper pid. A dev server routinely spawns children
# that never hold the listening socket (uvicorn --reload worker, vite/esbuild, webpack
# workers, a supervisor). The old teardown killed only the recorded pid (and, when a
# port tool was present, the single port holder), so those children were orphaned and
# kept their memory — every up/down cycle leaked one. These tests run with the suite's
# default ATE_PORT_TOOL=none (no port tool at all), the hardest case: teardown must
# still reap the tree via the recorded pid's descendants.

load helper

# A unique sentinel so the worker is always found and cleaned up; must not collide with anything else.
SENTINEL="ate_orphan_sentinel_918273645"

setup()    { common_setup; integration_only; }
teardown() {
  pkill -f "$SENTINEL" 2>/dev/null || true
  common_teardown
}

@test "down reaps a worker child that never holds the port (no orphan leak)" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  # The detached worker is `bash -c 'sleep 900' <SENTINEL>` (sentinel in argv for pgrep -f), never binds a port; the wrapper is the recorded pid.
  write_config "$repo" \
    "BACKEND_DIR='.'" \
    "BACKEND_CMD='bash -c \"sleep 900\" $SENTINEL & wait'"
  cd "$repo"

  ate up backend --scope backend >/dev/null 2>&1 || true
  # The worker is running.
  run pgrep -f "$SENTINEL"
  [ -n "$output" ]

  ate down backend >/dev/null 2>&1 || true
  sleep 1
  # After down the worker must be gone — the tree was reaped despite no port tool.
  run pgrep -f "$SENTINEL"
  [ -z "$output" ]
}
