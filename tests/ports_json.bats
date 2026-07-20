#!/usr/bin/env bats
# `ataegina ports --json` — the machine-readable slot object for agents.
#
# Spec (docs/design/agent-native.md): `ports --json` prints ONE line of JSON on
# stdout — the shared slot object {index, repo_root, frontend{port,url},
# backend{port,url}, log_dir, db} — and nothing else (no [ate] log prefix). `db`
# is null when no database is configured; db.url is null when DB_NAME is set but
# DB_URL_TEMPLATE is not. Plain `ports` (no flag) keeps its human output.
#
# Hermetic: ATE_PORT_TOOL=none, temp registry. Default bases 5173/8000, so index
# 0 -> 5173/8000 and index 1 -> 5174/8001.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  DBCFG=(
    "DB_NAME=myapp"
    "DB_KIND=custom"
    "DB_SUFFIX=_wt"
    "DB_URL_VAR=DATABASE_URL"
    "DB_URL_TEMPLATE='postgres://localhost:5432/\$ATE_DB_NAME'"
    "DB_AUTO_CREATE=0"
  )
}
teardown() { common_teardown; }

# Parse the output as JSON with python3 when present (proves it is real JSON, not
# just grep-matching text). A no-op skip-of-assertion when python3 is absent.
assert_valid_json() {
  command -v python3 >/dev/null 2>&1 || return 0
  printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "ports --json emits one line of valid JSON, no log prefix (primary, no db)" {
  cd "$REPO"
  run ate ports --json
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"index":0,'
  echo "$output" | grep -q '"frontend":{"port":5173,"url":"http://localhost:5173"}'
  echo "$output" | grep -q '"backend":{"port":8000,"url":"http://localhost:8000"}'
  echo "$output" | grep -q '"db":null}'
  # The human "[ate]" prefix must NOT leak into machine output.
  echo "$output" | grep -qv '\[ate\]'
}

@test "ports --json reflects a linked worktree's own ports (index 1)" {
  wt="$(add_worktree "$REPO" wtA)"
  cd "$wt"
  run ate ports --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"index":1,'
  echo "$output" | grep -q '"frontend":{"port":5174,"url":"http://localhost:5174"}'
  echo "$output" | grep -q '"backend":{"port":8001,"url":"http://localhost:8001"}'
}

@test "ports --json includes db name + url for a worktree when DB is configured" {
  write_config "$REPO" "${DBCFG[@]}"
  wt="$(add_worktree "$REPO" wtA)"
  cd "$wt"
  run ate ports --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"db":{"name":"myapp_wt1","url":"postgres://localhost:5432/myapp_wt1"}'
}

@test "ports --json db.url is null when DB_NAME set but DB_URL_TEMPLATE unset" {
  write_config "$REPO" \
    "DB_NAME=myapp" "DB_KIND=custom" "DB_SUFFIX=_wt" "DB_AUTO_CREATE=0"
  wt="$(add_worktree "$REPO" wtA)"
  cd "$wt"
  run ate ports --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"db":{"name":"myapp_wt1","url":null}'
}

@test "ports --json primary keeps the unsuffixed db name" {
  write_config "$REPO" "${DBCFG[@]}"
  cd "$REPO"
  run ate ports --json
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"db":{"name":"myapp","url":"postgres://localhost:5432/myapp"}'
}

@test "ports --json repo_root is the worktree path, JSON-escaped" {
  # A path with a space is a legal JSON string (no escaping needed) but must
  # round-trip intact; proves repo_root is emitted through the escaper. Compare
  # against the git-resolved toplevel (what ataegina uses for TREE), not the raw
  # mktemp path: on macOS $TMPDIR is a symlink (/var -> /private/var) that git
  # resolves, so the raw path would never match.
  spaced="$ATE_TMP/repo dir"
  R="$(make_repo "$spaced")"
  EXP="$(cd "$R" && git rev-parse --show-toplevel)"
  cd "$R"
  run ate ports --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -qF "\"repo_root\":\"$EXP\""
}

@test "ports --json escapes quotes and backslashes in repo_root (stays valid JSON)" {
  # A path containing a double-quote and a backslash would produce INVALID JSON if
  # emitted raw; python's json.load must still accept it. Locks the escaper (and
  # its backslash-first ordering). Linux permits both chars in a directory name.
  tricky="$ATE_TMP/re\\po\"x"
  R="$(make_repo "$tricky")"
  EXP="$(cd "$R" && git rev-parse --show-toplevel)"
  cd "$R"
  run ate ports --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  # If python3 is present, confirm the decoded repo_root equals the real path
  # (git-resolved, so it matches on macOS's symlinked $TMPDIR too).
  if command -v python3 >/dev/null 2>&1; then
    got="$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["repo_root"])')"
    [ "$got" = "$EXP" ]
  fi
}

@test "ports (no flag) still prints the human table" {
  cd "$REPO"
  run ate ports
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'frontend: http://localhost:5173'
  echo "$output" | grep -q 'backend:  http://localhost:8000'
}

@test "ports rejects an unknown argument" {
  cd "$REPO"
  run ate ports --bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "unknown argument"
}

@test "completion advertises ports --json (bash + zsh)" {
  run ate completion bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '[ (|]ports[|)].*--json'
  run ate completion zsh
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '[ (|]ports[|)].*compadd -- --json'
}
