#!/usr/bin/env bats
# `list` (valid + stale entries) and the `move` new-slot-in-use warning.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  BIN="$ATE_TMP/bin"; mkdir -p "$BIN"
}
teardown() { common_teardown; }

reg() { ( cd "$1" && env ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none bash "$ATE_SCRIPT" ports >/dev/null ); }

@test "list prints the primary, valid worktrees, and flags stale ones" {
  local wt1 wt2
  wt1="$(add_worktree "$REPO" wA)"; wt2="$(add_worktree "$REPO" wB)"
  reg "$wt1"; reg "$wt2"
  git -C "$REPO" worktree remove --force "$wt2"     # wt2 dir gone -> stale
  cd "$REPO"
  run ate list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "primary"
  echo "$output" | grep -qF "$wt1"                  # a valid entry
  echo "$output" | grep -qi "stale"                 # the removed one
}

@test "move warns when the new slot's ports are already in use" {
  # A fake ss that reports the NEW backend slot (8000 + 7) as listening.
  cat > "$BIN/ss" <<'EOF'
#!/usr/bin/env bash
want="${FAKE_PORT:-0}"; q=""
for a in "$@"; do case "$a" in -*) : ;; *) q="$q $a" ;; esac; done
case "$q" in *"sport = :$want"*) echo "LISTEN 0 128 127.0.0.1:$want 0.0.0.0:*" ;; *) exit 0 ;; esac
EOF
  chmod +x "$BIN/ss"
  local wt; wt="$(add_worktree "$REPO" wC)"
  reg "$wt"
  cd "$wt"
  run env PATH="$BIN:$PATH" ATE_PORT_TOOL=ss FAKE_PORT=8007 \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" move 7
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already in use"
}
