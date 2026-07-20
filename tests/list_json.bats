#!/usr/bin/env bats
# `ataegina list --json` — the fleet view: every registered worktree as a JSON array.
#
# Spec (docs/design/agent-native.md): a JSON array (primary at index 0 first, then
# each registry entry) of the shared slot shape plus two list-only fields: `stale`
# (the worktree directory is gone) and `live` (coarse best-effort: any derived port
# is listening — always false under ATE_PORT_TOOL=none). The view a supervising
# agent uses to see all its workers at once. Human `list` output is unchanged.
#
# Hermetic. Indices are assigned by running a read command in each worktree. `live`
# is exercised with a fake `ss` reporting one worktree's frontend port LISTEN.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  BIN="$ATE_TMP/bin"; mkdir -p "$BIN"
  FE=53100; BE=54100
  write_config "$REPO" "FRONT_PORT_BASE=$FE" "BACK_PORT_BASE=$BE"
  DBCFG=(
    "FRONT_PORT_BASE=$FE" "BACK_PORT_BASE=$BE"
    "DB_NAME=myapp" "DB_KIND=custom" "DB_SUFFIX=_wt"
    "DB_URL_TEMPLATE='postgres://localhost:5432/\$ATE_DB_NAME'"
  )
}
teardown() { common_teardown; }

assert_valid_json() {
  command -v python3 >/dev/null 2>&1 || return 0
  printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

# Register a worktree (assign its index) by running a read command from inside it.
register() { ( cd "$1" && ate ports >/dev/null ); }

make_fake_ss() {
  cat > "$BIN/ss" <<'EOF'
#!/usr/bin/env bash
want="${FAKE_PORT:-0}"; query=""
for a in "$@"; do case "$a" in -*) : ;; *) query="$query $a" ;; esac; done
case "$query" in *"sport = :$want"*) echo "LISTEN 0 128 127.0.0.1:$want 0.0.0.0:*" ;; *) exit 0 ;; esac
EOF
  chmod +x "$BIN/ss"
}

@test "list --json is a JSON array; primary is index 0, not stale, not live" {
  cd "$REPO"
  run ate list --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '^\[{"index":0,'
  echo "$output" | grep -q '"repo_root":"'"$REPO"'"'
  echo "$output" | grep -q '"stale":false,"live":false}'
  echo "$output" | grep -q '"db":null'
}

@test "list --json includes each registered worktree with its own ports" {
  local a b
  a="$(add_worktree "$REPO" wtA)"; register "$a"
  b="$(add_worktree "$REPO" wtB)"; register "$b"
  cd "$REPO"
  run ate list --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"index":1,"repo_root":"'"$a"'","frontend":{"port":53101,'
  echo "$output" | grep -q '"index":2,"repo_root":"'"$b"'","frontend":{"port":53102,'
  # Parseable as a 3-element array (primary + 2).
  if command -v python3 >/dev/null 2>&1; then
    n="$(printf '%s' "$output" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
    [ "$n" -eq 3 ]
  fi
}

@test "list --json marks an entry stale when its worktree directory is gone" {
  local a
  a="$(add_worktree "$REPO" wtA)"; register "$a"
  rm -rf "$a"          # registry still holds the entry; prune not run
  cd "$REPO"
  run ate list --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"index":1,"repo_root":"'"$a"'".*"stale":true,"live":false}'
}

@test "list --json marks an entry live when a derived port is listening" {
  local a
  a="$(add_worktree "$REPO" wtA)"; register "$a"    # index 1 -> frontend 53101
  make_fake_ss
  cd "$REPO"
  run env PATH="$BIN:$PATH" ATE_PORT_TOOL=ss FAKE_PORT=53101 \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" list --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"index":1,.*"stale":false,"live":true}'
}

@test "list --json derives per-worktree db names (primary unsuffixed, wtN suffixed)" {
  write_config "$REPO" "${DBCFG[@]}"
  local a
  a="$(add_worktree "$REPO" wtA)"
  cp "$REPO/ataegina.config.sh" "$a/ataegina.config.sh"
  register "$a"
  cd "$REPO"
  run ate list --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"index":0,.*"db":{"name":"myapp","url":"postgres://localhost:5432/myapp"}'
  echo "$output" | grep -q '"index":1,.*"db":{"name":"myapp_wt1","url":"postgres://localhost:5432/myapp_wt1"}'
}

@test "list --json on a fresh repo is a single-element array (just the primary)" {
  cd "$REPO"
  run ate list --json
  [ "$status" -eq 0 ]
  if command -v python3 >/dev/null 2>&1; then
    n="$(printf '%s' "$output" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
    [ "$n" -eq 1 ]
  fi
}

@test "list (no flag) still prints the human table with the primary" {
  local a
  a="$(add_worktree "$REPO" wtA)"; register "$a"
  cd "$REPO"
  run ate list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "(primary)"
  echo "$output" | grep -qE "^1	$a"
}

@test "list (no flag) flags a stale entry" {
  local a
  a="$(add_worktree "$REPO" wtA)"; register "$a"
  rm -rf "$a"
  cd "$REPO"
  run ate list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "stale"
}

@test "list rejects an unknown argument (exit 2)" {
  cd "$REPO"
  run ate list --bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "unknown argument"
}

@test "completion advertises list --json (bash + zsh)" {
  run ate completion bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '[ (|]list[|)].*--json'
  run ate completion zsh
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '[ (|]list[|)].*compadd -- --json'
}
