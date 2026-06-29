#!/usr/bin/env bats
# Index assignment + recycling, and port derivation.

load helper

setup()    { common_setup; }
teardown() { common_teardown; }

@test "primary checkout is index 0" {
  repo="$(make_repo "$ATE_TMP/repo")"
  cd "$repo"
  run ate ports
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "worktree #0"
  echo "$output" | grep -q "frontend: http://localhost:5173"
  echo "$output" | grep -q "backend:  http://localhost:8000"
}

@test "first added worktree gets index 1" {
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wtA)"
  cd "$wt"
  run ate ports
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "worktree #1"
  echo "$output" | grep -q "frontend: http://localhost:5174"
  echo "$output" | grep -q "backend:  http://localhost:8001"
}

@test "second worktree gets index 2, indices are sticky across runs" {
  repo="$(make_repo "$ATE_TMP/repo")"
  wtA="$(add_worktree "$repo" wtA)"
  wtB="$(add_worktree "$repo" wtB)"
  ( cd "$wtA" && ate ports >/dev/null )   # claim index 1
  ( cd "$wtB" && ate ports >/dev/null )   # claim index 2

  cd "$wtA"
  run ate ports
  echo "$output" | grep -q "worktree #1"
  cd "$wtB"
  run ate ports
  echo "$output" | grep -q "worktree #2"

  # Re-run wtA: still index 1 (sticky, not reassigned).
  cd "$wtA"
  run ate ports
  echo "$output" | grep -q "worktree #1"
}

@test "a freed slot is reused after its registry row is removed (gap reuse)" {
  repo="$(make_repo "$ATE_TMP/repo")"
  wtA="$(add_worktree "$repo" wtA)"
  wtB="$(add_worktree "$repo" wtB)"
  ( cd "$wtA" && ate ports >/dev/null )   # index 1
  ( cd "$wtB" && ate ports >/dev/null )   # index 2

  # Find the per-repo registry file and drop the index-1 row, creating a gap.
  # (Match on the leading index column; the stored path may be symlink-resolved,
  # so matching on the path string is unreliable on macOS where /tmp -> /private.)
  reg="$(find "$ATE_TMP/registry/repos" -type f | head -n1)"
  [ -n "$reg" ]
  grep -v "^1$(printf '\t')" "$reg" > "$reg.tmp" || true
  mv "$reg.tmp" "$reg"

  # A brand new worktree should claim the lowest free index, which is now 1.
  wtC="$(add_worktree "$repo" wtC)"
  cd "$wtC"
  run ate ports
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "worktree #1"
}

@test "ATE_INDEX overrides the assigned index for one run" {
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wtA)"
  cd "$wt"
  run env ATE_INDEX=7 \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" ports
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "worktree #7"
  echo "$output" | grep -q "frontend: http://localhost:5180"
  echo "$output" | grep -q "backend:  http://localhost:8007"
}

@test "ports derive from custom FRONT_PORT_BASE / BACK_PORT_BASE for several N" {
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "FRONT_PORT_BASE=4000" "BACK_PORT_BASE=9000"

  # Primary (N=0): bases as-is.
  cd "$repo"
  run ate ports
  echo "$output" | grep -q "frontend: http://localhost:4000"
  echo "$output" | grep -q "backend:  http://localhost:9000"

  # Worktree N=1: bases + 1. Copy the config into the worktree (per-tree config).
  wt="$(add_worktree "$repo" wtA)"
  write_config "$wt" "FRONT_PORT_BASE=4000" "BACK_PORT_BASE=9000"
  cd "$wt"
  run ate ports
  echo "$output" | grep -q "worktree #1"
  echo "$output" | grep -q "frontend: http://localhost:4001"
  echo "$output" | grep -q "backend:  http://localhost:9001"
}

@test "log dir path tracks the index" {
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wtA)"
  cd "$wt"
  run ate ports
  echo "$output" | grep -q "logs:     $ATE_TMP/logs/ate-wt1"
}
