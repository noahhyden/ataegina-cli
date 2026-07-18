#!/usr/bin/env bats
# `prune` drops registry entries whose worktree directory is gone, and frees those
# indices for reuse. Hermetic (registry-only; no servers). Previously untested.

load helper

setup()    { common_setup; }
teardown() { common_teardown; }

# The per-repo registry file (excludes any lock dir).
reg_file() { find "$ATE_TMP/registry/repos" -type f ! -name '*.lock' 2>/dev/null | head -n1; }

@test "prune removes a stale entry but keeps a live one" {
  local repo wtA wtB
  repo="$(make_repo "$ATE_TMP/repo")"
  wtA="$(add_worktree "$repo" a)"
  wtB="$(add_worktree "$repo" b)"
  ( cd "$wtA" && ate ports >/dev/null )   # index 1
  ( cd "$wtB" && ate ports >/dev/null )   # index 2

  # Remove wtA's directory -> its registry entry is now stale.
  git -C "$repo" worktree remove --force "$wtA"

  cd "$repo"
  run ate prune
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "pruned 1 stale"

  local reg; reg="$(reg_file)"
  run grep -F "$wtA" "$reg"; [ "$status" -ne 0 ]   # stale entry gone
  run grep -F "$wtB" "$reg"; [ "$status" -eq 0 ]   # live entry kept
}

@test "a pruned index is recycled by the next new worktree" {
  local repo wtA wtC
  repo="$(make_repo "$ATE_TMP/repo")"
  wtA="$(add_worktree "$repo" a)"
  ( cd "$wtA" && ate ports >/dev/null )   # index 1
  git -C "$repo" worktree remove --force "$wtA"
  ( cd "$repo" && ate prune >/dev/null )

  # The next new worktree reuses the freed index 1.
  wtC="$(add_worktree "$repo" c)"
  cd "$wtC"
  run ate ports
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "worktree #1"
}

@test "prune with nothing stale is a clean no-op that keeps live entries" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" a)"
  ( cd "$wt" && ate ports >/dev/null )    # index 1, dir still present

  cd "$repo"
  run ate prune
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "pruned 0 stale"
  local reg; reg="$(reg_file)"
  run grep -F "$wt" "$reg"; [ "$status" -eq 0 ]   # live entry intact
}

@test "prune with no registry yet is a graceful no-op" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  cd "$repo"           # primary only; no worktrees registered
  run ate prune
  [ "$status" -eq 0 ]
}
