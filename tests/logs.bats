#!/usr/bin/env bats
# `ataegina logs` — full branch coverage of cmd_logs, driven hermetically: the log
# files are the source of truth (up runs servers detached), so we just create them
# under this tree's log dir and follow/tail. No real servers. `--no-follow` keeps
# `exec tail` finite; one follow case uses `timeout` to exercise the `-f` path.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  LD="$ATE_TMP/logs/ate-wt0"          # index 0 (primary) -> LOG_DIR_BASE + 0
  mkdir -p "$LD"
}
teardown() { common_teardown; }

@test "logs backend --no-follow prints the backend log" {
  echo "BE-LINE-xyz" > "$LD/backend.log"
  cd "$REPO"
  run ate logs backend --no-follow
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "BE-LINE-xyz"
}

@test "logs frontend --no-follow prints the frontend log" {
  echo "FE-LINE-xyz" > "$LD/frontend.log"
  cd "$REPO"
  run ate logs frontend --no-follow
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "FE-LINE-xyz"
}

@test "logs both --no-follow multiplexes both logs" {
  echo "BE-both" > "$LD/backend.log"
  echo "FE-both" > "$LD/frontend.log"
  cd "$REPO"
  run ate logs both --no-follow
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "BE-both"
  echo "$output" | grep -q "FE-both"
}

@test "logs both with only the frontend present tails just it" {
  echo "FE-only" > "$LD/frontend.log"
  cd "$REPO"
  run ate logs both --no-follow
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "FE-only"
}

@test "logs -n N limits the tail length" {
  printf 'l1\nl2\nl3\nl4\n' > "$LD/backend.log"
  cd "$REPO"
  run ate logs backend --no-follow -n 2
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "l4"
  refute_output_has "l1"
}

@test "logs -nN (glued form) also limits the tail length" {
  printf 'a1\na2\na3\n' > "$LD/backend.log"
  cd "$REPO"
  run ate logs backend --no-follow -n1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "a3"
  refute_output_has "a1"
}

@test "logs with an unknown argument exits 2" {
  cd "$REPO"
  run ate logs bogus-arg
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "unknown argument"
}

@test "logs backend errors when there is no backend log yet" {
  cd "$REPO"
  run ate logs backend --no-follow
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "no backend log"
}

@test "logs frontend errors when there is no frontend log yet" {
  cd "$REPO"
  run ate logs frontend --no-follow
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "no frontend log"
}

@test "logs both errors when neither log exists" {
  cd "$REPO"
  run ate logs both --no-follow
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "no logs yet"
}

@test "logs (follow, default) exercises the -f path and streams the log" {
  # `timeout` is GNU-only; macOS ships it as `gtimeout` (coreutils) or not at all.
  local to; to="$(command -v timeout || command -v gtimeout || true)"
  [ -n "$to" ] || skip "no timeout/gtimeout available to bound the follow path"
  echo "FOLLOW-line" > "$LD/backend.log"
  cd "$REPO"
  # Default follow=1 -> `exec tail -f` blocks; timeout ends it. 124 = timed out.
  run env ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    "$to" 2 bash "$ATE_SCRIPT" logs backend
  echo "$output" | grep -q "FOLLOW-line"
}
