#!/usr/bin/env bats
# Scope detection: classify what surface a worktree's diff touches.
#
# We read the resolved scope off `ataegina doctor`, which prints a
#   scope: <value> (...)
# line computed by the same resolve_scope chain `up` uses (minus side effects).
# Scope detection only runs for non-primary worktrees (the primary is always
# `both`), so every case here works in an added worktree branched off main, with
# a config that declares FRONTEND_DIR / BACKEND_DIR.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  # A config the scope detector can use to bucket paths.
  CFG=("FRONT_PORT_BASE=5173" "BACK_PORT_BASE=8000" \
       "FRONTEND_DIR=frontend" "BACKEND_DIR=backend")
}
teardown() { common_teardown; }

# Echo the scope value doctor resolved (the word after "scope:").
doctor_scope() {
  ate doctor 2>/dev/null | sed -n 's/^\[ok\][[:space:]]*scope:[[:space:]]*\([a-z]*\).*/\1/p' | head -n1
}

@test "frontend-only change resolves to frontend" {
  wt="$(add_worktree "$REPO" wtA work)"
  write_config "$wt" "${CFG[@]}"
  echo "change" >> "$wt/frontend/app.js"
  git -C "$wt" commit -q -am "fe change"
  cd "$wt"
  run env ATE_BASE_BRANCH=main ATE_PORT_TOOL=none \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" doctor
  echo "$output" | grep -qE '^\[ok\][[:space:]]+scope: frontend'
}

@test "backend-only change resolves to backend" {
  wt="$(add_worktree "$REPO" wtA work)"
  write_config "$wt" "${CFG[@]}"
  echo "change" >> "$wt/backend/server.py"
  git -C "$wt" commit -q -am "be change"
  cd "$wt"
  run env ATE_BASE_BRANCH=main ATE_PORT_TOOL=none \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" doctor
  echo "$output" | grep -qE '^\[ok\][[:space:]]+scope: backend'
}

@test "a change outside both dirs resolves to both" {
  wt="$(add_worktree "$REPO" wtA work)"
  write_config "$wt" "${CFG[@]}"
  echo "shared lib change" >> "$wt/README.md"
  git -C "$wt" commit -q -am "root change"
  cd "$wt"
  run env ATE_BASE_BRANCH=main ATE_PORT_TOOL=none \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" doctor
  echo "$output" | grep -qE '^\[ok\][[:space:]]+scope: both'
}

@test "frontend AND backend touched (no other) resolves to both" {
  wt="$(add_worktree "$REPO" wtA work)"
  write_config "$wt" "${CFG[@]}"
  echo "fe" >> "$wt/frontend/app.js"
  echo "be" >> "$wt/backend/server.py"
  git -C "$wt" commit -q -am "both change"
  cd "$wt"
  run env ATE_BASE_BRANCH=main ATE_PORT_TOOL=none \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" doctor
  echo "$output" | grep -qE '^\[ok\][[:space:]]+scope: both'
}

@test "empty diff vs the base resolves to none (auto), annotated as -> both on up" {
  wt="$(add_worktree "$REPO" wtA work)"
  write_config "$wt" "${CFG[@]}"
  # No changes vs main.
  cd "$wt"
  run env ATE_BASE_BRANCH=main ATE_PORT_TOOL=none \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" doctor
  # doctor reports the raw auto-detected none, annotating the up-time nudge.
  echo "$output" | grep -qE '^\[ok\][[:space:]]+scope: none \(auto -> both on'
}

@test "ATE_BASE_BRANCH selects the ref scope diffs against" {
  # Make a second base branch `dev` that already contains a backend change, then
  # branch the worktree off dev and add a frontend change. Diffed against dev the
  # scope is frontend (only the new FE change); diffed against main it would be
  # both (FE + the BE change dev carries). This proves the base resolves to
  # ATE_BASE_BRANCH.
  git -C "$REPO" checkout -q -b dev
  echo "dev-only be" >> "$REPO/backend/server.py"
  git -C "$REPO" commit -q -am "be change on dev"
  git -C "$REPO" checkout -q main

  wt="$REPO-wtA"
  git -C "$REPO" worktree add -q -b work "$wt" dev >/dev/null 2>&1
  write_config "$wt" "${CFG[@]}"
  echo "fe change" >> "$wt/frontend/app.js"
  git -C "$wt" commit -q -am "fe change on work"
  cd "$wt"

  run env ATE_BASE_BRANCH=dev ATE_PORT_TOOL=none \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" doctor
  echo "$output" | grep -qE '^\[ok\][[:space:]]+scope: frontend'

  run env ATE_BASE_BRANCH=main ATE_PORT_TOOL=none \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" doctor
  echo "$output" | grep -qE '^\[ok\][[:space:]]+scope: both'
}
