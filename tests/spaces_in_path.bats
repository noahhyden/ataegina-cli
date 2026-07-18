#!/usr/bin/env bats
# Regression: a repo whose path contains a SPACE must still be detected as its own
# primary (index 0). `git worktree list --porcelain` prints the path unquoted, so
# parsing it with `awk '{print $2}'` truncated it at the first space, making
# TREE != PRIMARY even in the primary checkout — the primary then lost index 0
# (and, with a DB configured, its shared unsuffixed database + base ports).

load helper

setup()    { common_setup; }
teardown() { common_teardown; }

@test "a primary at a path containing a space is still index 0" {
  repo="$(make_repo "$ATE_TMP/my repo dir")"

  cd "$repo"
  run ate ports
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "worktree #0"
  # The reported path is not truncated at the space.
  echo "$output" | grep -q "my repo dir"
}

@test "a worktree of a spaced-path repo gets a nonzero index" {
  repo="$(make_repo "$ATE_TMP/my repo dir")"
  wt="$(add_worktree "$repo" feat)"

  cd "$wt"
  run ate ports
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "worktree #1"
}

@test "list shows the full spaced primary path (not truncated)" {
  repo="$(make_repo "$ATE_TMP/my repo dir")"

  cd "$repo"
  run ate list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "my repo dir (primary)"
}
