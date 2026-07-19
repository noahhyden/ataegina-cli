#!/usr/bin/env bats
# Regression: a linked worktree must inherit the PRIMARY checkout's config. The config
# carries machine-specific ports/commands, so it's naturally .gitignored — and git does
# not copy untracked files into a `git worktree add` tree. So a fresh worktree had NO
# config and `up`/`db` there failed with "no backend/database configured", breaking the
# per-worktree workflow the tool is built for. load_config now falls back to
# <primary>/ataegina.config.sh (the worktree's own config still wins if present).

load helper

setup()    { common_setup; }
teardown() { common_teardown; }

@test "a linked worktree with no own config inherits the primary's" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" \
    "BACKEND_DIR='.'" "BACKEND_CMD='sleep 1'" \
    "DB_NAME=shop" "DB_KIND=sqlite" "DB_SUFFIX=_wt"
  wt="$(add_worktree "$repo" wt)"
  # The worktree genuinely has no config of its own, and there is no global one.
  [ ! -f "$wt/ataegina.config.sh" ]
  [ ! -f "$ATE_TMP/registry/ataegina.config.sh" ]

  cd "$wt"
  run ate doctor
  [ "$status" -eq 0 ]
  # A config loaded, and it is NOT the worktree's own (it has none) — so it came from
  # the primary. (Assert on the /ataegina.config.sh suffix, not an exact primary path:
  # macOS resolves /tmp -> /private/tmp, so git's PRIMARY path is spelled differently
  # than the test's $repo, though it is the same file.)
  echo "$output" | grep -q "config: loaded .*/ataegina.config.sh"
  refute_output_has "config: loaded $wt/ataegina.config.sh"
  # Config really took effect: DB name derives per-worktree from the inherited DB_NAME
  # (the worktree has no config and there is no global one, so this can only be the
  # primary's DB_NAME=shop) — the functional proof of inheritance.
  run ate db name
  [ "$output" = "shop_wt1" ]
  # And the backend is considered configured (would fail "no backend configured" before).
  cd "$wt"
  run ate doctor
  echo "$output" | grep -q "backend start: BACKEND_CMD is set"
}

@test "a worktree's own config still wins over the primary's" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "DB_NAME=primary" "DB_KIND=sqlite"
  wt="$(add_worktree "$repo" wt)"
  # Give the worktree its OWN config.
  write_config "$wt" "DB_NAME=ownconfig" "DB_KIND=sqlite"

  cd "$wt"
  run ate db name
  # index 1 -> ownconfig_wt1 (worktree config), not primary_wt1.
  [ "$output" = "ownconfig_wt1" ]
}
