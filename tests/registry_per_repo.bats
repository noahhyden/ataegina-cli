#!/usr/bin/env bats
# The registry is per-repo: two unrelated primary checkouts each get index 0 and
# distinct registry files under repos/<key>.

load helper

setup()    { common_setup; }
teardown() { common_teardown; }

@test "two unrelated repos each see their primary as index 0" {
  repoA="$(make_repo "$ATE_TMP/repoA")"
  repoB="$(make_repo "$ATE_TMP/repoB")"

  cd "$repoA"
  run ate ports
  echo "$output" | grep -q "worktree #0"

  cd "$repoB"
  run ate ports
  echo "$output" | grep -q "worktree #0"
}

@test "each repo's worktrees get an independent index space" {
  repoA="$(make_repo "$ATE_TMP/repoA")"
  repoB="$(make_repo "$ATE_TMP/repoB")"
  wtA="$(add_worktree "$repoA" wt)"
  wtB="$(add_worktree "$repoB" wt)"

  # First worktree in EACH repo is index 1, independently (not 1 then 2).
  cd "$wtA"
  run ate ports
  echo "$output" | grep -q "worktree #1"
  cd "$wtB"
  run ate ports
  echo "$output" | grep -q "worktree #1"
}

@test "the two repos write distinct per-repo registry files" {
  repoA="$(make_repo "$ATE_TMP/repoA")"
  repoB="$(make_repo "$ATE_TMP/repoB")"
  ( cd "$(add_worktree "$repoA" wt)" && ate ports >/dev/null )
  ( cd "$(add_worktree "$repoB" wt)" && ate ports >/dev/null )

  # Two separate files under repos/, one per repo key.
  count="$(find "$ATE_TMP/registry/repos" -type f | wc -l | tr -d ' ')"
  [ "$count" -eq 2 ]
}

@test "ATE_REGISTRY pins one shared file across repos" {
  repoA="$(make_repo "$ATE_TMP/repoA")"
  repoB="$(make_repo "$ATE_TMP/repoB")"
  shared="$ATE_TMP/shared-registry"
  wtA="$(add_worktree "$repoA" wt)"
  wtB="$(add_worktree "$repoB" wt)"

  # With a single shared registry, the two worktrees share one index space:
  # the second one to register lands on index 2, not 1.
  cd "$wtA"
  run env ATE_REGISTRY="$shared" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" bash "$ATE_SCRIPT" ports
  echo "$output" | grep -q "worktree #1"

  cd "$wtB"
  run env ATE_REGISTRY="$shared" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" bash "$ATE_SCRIPT" ports
  echo "$output" | grep -q "worktree #2"

  [ -f "$shared" ]
}
