#!/usr/bin/env bats
# cmd_up branch coverage: argument validation, the auto-detected none->both nudge,
# the frontend-scope-with-shared-backend-down fallback, `--scope none`, and the
# not-in-a-git-worktree guard. Hermetic: backends/frontends are `true`, ATE_PORT_TOOL
# is none (so up starts nothing real; we only exercise the control flow).

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

@test "up --scope with an invalid value errors (exit 2)" {
  cd "$REPO"
  run ate up --scope bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "scope must be"
}

@test "up --scope=VALUE (glued form) is accepted" {
  cd "$REPO"
  run ate up backend --scope=backend
  [ "$status" -eq 0 ]
}

@test "up --scope=VALUE with an invalid value errors (exit 2)" {
  cd "$REPO"
  run ate up --scope=bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "scope must be"
}

@test "up with an unknown argument errors (exit 2)" {
  cd "$REPO"
  run ate up wat
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "unknown argument"
}

@test "up --scope none starts nothing and exits 0" {
  cd "$REPO"
  run ate up --scope none
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "scope: none"
}

@test "up on a worktree with no diff vs base auto-detects none, then nudges to both" {
  local wt; wt="$(add_worktree "$REPO" wtA)"
  # copy the config into the worktree (untracked file isn't carried across)
  cp "$REPO/ataegina.config.sh" "$wt/ataegina.config.sh"
  cd "$wt"
  run ate up                      # no --scope -> auto-detect; empty diff -> none -> both
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "no changes detected"
  echo "$output" | grep -qi "scope: both"
}

@test "up frontend when the shared backend is DOWN falls back to a local backend" {
  cd "$REPO"
  # Nothing is listening on the base backend port (ATE_PORT_TOOL=none also reports
  # 'not listening'), so the frontend scope must start a LOCAL backend.
  run ate up frontend --scope frontend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "shared backend on :54100 is DOWN"
}

@test "up outside a git worktree errors clearly" {
  local nogit="$ATE_TMP/plain"; mkdir -p "$nogit"
  cd "$nogit"
  run ate up
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not inside a git worktree"
}

@test "up frontend borrows the shared backend when it is UP (fake port tool)" {
  local bin="$ATE_TMP/bin"; mkdir -p "$bin"
  cat > "$bin/ss" <<'EOF'
#!/usr/bin/env bash
want="${FAKE_PORT:-0}"; q=""
for a in "$@"; do case "$a" in -*) : ;; *) q="$q $a" ;; esac; done
case "$q" in *"sport = :$want"*) echo "LISTEN 0 128 127.0.0.1:$want 0.0.0.0:*" ;; *) exit 0 ;; esac
EOF
  chmod +x "$bin/ss"
  local wt; wt="$(add_worktree "$REPO" wtShared)"
  cp "$REPO/ataegina.config.sh" "$wt/ataegina.config.sh"
  cd "$wt"
  # Report the BASE backend port (54100) as listening -> the shared-backend-UP path.
  run env PATH="$bin:$PATH" ATE_PORT_TOOL=ss FAKE_PORT=54100 \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" up frontend --scope frontend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "backend shared from :54100"
}

@test "down both dispatches to both sides" {
  cd "$REPO"
  run ate down both
  echo "$output" | grep -qiE "nothing to stop|stopped on"
}

@test "down frontend dispatches to the frontend side" {
  cd "$REPO"
  run ate down frontend
  echo "$output" | grep -qiE "nothing to stop|stopped on"
}
