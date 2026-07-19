#!/usr/bin/env bats
# `ataegina restart [both|backend|frontend] [--scope X]` — stop this worktree's
# servers, then start them again (a `down` followed by `up`).
#
# Spec: restart forwards all its arguments to `up` (which resolves the final
# scope), and its STOP phase mirrors the leading mode word (default both) so
# `restart backend` bounces only the backend. Exit status is `up`'s.
#
# Hermetic (like up_coverage.bats): FRONTEND_CMD/BACKEND_CMD are `true`, so the
# start hooks exit immediately and nothing real is launched — we exercise the
# control flow (stop-then-start, mode/scope forwarding) only. ATE_PORT_TOOL=none.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  write_config "$REPO" \
    "FRONT_PORT_BASE=53100" "BACK_PORT_BASE=54100" \
    "FRONTEND_DIR='.'" "FRONTEND_CMD='true'" \
    "BACKEND_DIR='.'"  "BACKEND_CMD='true'"
}
teardown() { common_teardown; }

@test "restart stops both sides then starts (down phase + up phase both run)" {
  cd "$REPO"
  run ate restart --scope both
  [ "$status" -eq 0 ]
  # Down phase (nothing running yet) reports both slots...
  echo "$output" | grep -qi "frontend: nothing to stop"
  echo "$output" | grep -qi "backend: nothing to stop"
  # ...and the up phase announces the scope it started.
  echo "$output" | grep -qi "scope:"
}

@test "restart backend bounces only the backend (frontend is not stopped)" {
  cd "$REPO"
  run ate restart backend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "backend: nothing to stop"
  # The frontend stop must NOT run for a backend-scoped restart.
  refute_output_has "frontend: nothing to stop"
}

@test "restart frontend bounces only the frontend (backend stop is not run)" {
  cd "$REPO"
  run ate restart frontend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "frontend: nothing to stop"
  # ate_stop_backend must not run; "backend: nothing to stop" comes only from it.
  refute_output_has "backend: nothing to stop"
}

@test "restart forwards --scope none to up (starts nothing)" {
  cd "$REPO"
  run ate restart --scope none
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "scope: none"
}

@test "restart forwards the --scope=VALUE glued form to up" {
  cd "$REPO"
  run ate restart backend --scope=backend
  [ "$status" -eq 0 ]
}

@test "restart propagates up's argument-validation failure (invalid scope)" {
  cd "$REPO"
  run ate restart --scope bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "scope must be"
}

@test "restart with an unknown argument errors via up (exit 2)" {
  cd "$REPO"
  run ate restart wat
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "unknown argument"
}

@test "restart outside a git worktree errors clearly" {
  cd "$ATE_TMP"
  run ate restart
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not inside a git worktree"
}
