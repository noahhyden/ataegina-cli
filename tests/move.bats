#!/usr/bin/env bats
# `ataegina move N` relocates THIS worktree to index N (and therefore a new
# port pair), rewriting the per-repo registry. It exists so a worktree whose
# auto-assigned slot is permanently occupied by something ataegina doesn't
# manage can be moved without hand-editing the registry.

load helper

setup()    { common_setup; }
teardown() { common_teardown; }

@test "move relocates a worktree to the requested index" {
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"

  # Auto-assigned to #1 first.
  run ate ports
  echo "$output" | grep -q "worktree #1"

  run ate move 4
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "index #4"

  # The new index sticks on subsequent invocations.
  run ate ports
  echo "$output" | grep -q "worktree #4"
}

@test "move reports the new derived ports" {
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"
  ate ports >/dev/null

  FRONT_PORT_BASE=5173 BACK_PORT_BASE=8000 run ate move 4
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "localhost:5177"   # 5173 + 4
  echo "$output" | grep -q "localhost:8004"   # 8000 + 4
}

@test "move leaves the old index free for reuse" {
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"
  ate ports >/dev/null            # #1
  ate move 4 >/dev/null

  # A second worktree now claims the freed #1, not #2.
  wt2="$(add_worktree "$repo" wt2)"
  cd "$wt2"
  run ate ports
  echo "$output" | grep -q "worktree #1"
}

@test "move refuses an index already held by another live worktree" {
  repo="$(make_repo "$ATE_TMP/repo")"
  wt1="$(add_worktree "$repo" wt1)"
  wt2="$(add_worktree "$repo" wt2)"
  ( cd "$wt1" && ate ports >/dev/null )   # #1
  ( cd "$wt2" && ate ports >/dev/null )   # #2

  cd "$wt1"
  run ate move 2
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "already assigned"
}

@test "move rejects index 0 and non-numeric targets" {
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"
  ate ports >/dev/null

  run ate move 0
  [ "$status" -ne 0 ]

  run ate move abc
  [ "$status" -ne 0 ]

  run ate move
  [ "$status" -ne 0 ]
}

@test "the primary checkout cannot be moved" {
  repo="$(make_repo "$ATE_TMP/repo")"
  cd "$repo"
  run ate move 3
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "primary"
}
