#!/usr/bin/env bats
# `ataegina up --json` — one machine-readable slot object + what this invocation did.
#
# Spec (docs/design/agent-native.md): after starting the resolved scope, print ONE
# JSON line on stdout — the slot shape plus `started` (surfaces we launched) and
# per-surface `ready` (honoring --wait's polling; a plain --json does a single
# immediate check). All human log/hook output goes to stderr, so stdout is pure
# JSON. Exit 0 without --wait (fire-and-forget); with --wait, 75 if a launched
# server is not ready by the deadline.
#
# Hermetic: `true` backends/frontends, ATE_PORT_TOOL=none (nothing binds -> ready
# false). The ready=true path uses a fake `ss` reporting the derived backend port
# LISTEN. We capture stdout and stderr into separate variables (portable across
# bats versions — no `run --separate-stderr`) to prove stdout stays pure JSON.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  BIN="$ATE_TMP/bin"; mkdir -p "$BIN"
  BE=54100; FE=53100
  write_config "$REPO" \
    "FRONT_PORT_BASE=$FE" "BACK_PORT_BASE=$BE" \
    "FRONTEND_DIR='.'" "FRONTEND_CMD='true'" \
    "BACKEND_DIR='.'"  "BACKEND_CMD='true'"
}
teardown() { common_teardown; }

assert_valid_json() {
  command -v python3 >/dev/null 2>&1 || return 0
  printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

make_fake_ss() {
  cat > "$BIN/ss" <<'EOF'
#!/usr/bin/env bash
want="${FAKE_PORT:-0}"; query=""
for a in "$@"; do case "$a" in -*) : ;; *) query="$query $a" ;; esac; done
case "$query" in *"sport = :$want"*) echo "LISTEN 0 128 127.0.0.1:$want 0.0.0.0:*" ;; *) exit 0 ;; esac
EOF
  chmod +x "$BIN/ss"
}

# Run ataegina capturing stdout in $OUT, stderr in $ERR, exit code in $RC — kept
# separate so we can assert stdout is pure JSON. $PORT_TOOL/$FAKE_PORT default off.
jrun() {
  local errf; errf="$(mktemp)"
  # `&& RC=0 || RC=$?` keeps a non-zero exit (e.g. 75 under --wait) from tripping
  # bats' errexit, while still recording the real code in RC.
  OUT="$(env PATH="$BIN:$PATH" ATE_PORT_TOOL="${PORT_TOOL:-none}" FAKE_PORT="${FAKE_PORT:-0}" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" "$@" 2>"$errf")" && RC=0 || RC=$?
  ERR="$(cat "$errf")"; rm -f "$errf"
}

@test "up --json: stdout is pure JSON, human output on stderr" {
  cd "$REPO"
  jrun up backend --scope backend --json
  [ "$RC" -eq 0 ]
  assert_valid_json "$OUT"
  printf '%s' "$OUT" | grep -qv '\[ate\]'   # no human prefix leaked to stdout
  printf '%s' "$ERR" | grep -q '\[ate\]'     # the logs went to stderr instead
}

@test "up --json reports 'started' and per-surface 'ready' (false when not bound)" {
  cd "$REPO"
  jrun up backend --scope backend --json
  [ "$RC" -eq 0 ]
  printf '%s' "$OUT" | grep -q '"started":\["backend"\]'
  printf '%s' "$OUT" | grep -q '"ready":{"backend":false}'
}

@test "up --json on the primary starts both surfaces" {
  cd "$REPO"
  jrun up --json
  [ "$RC" -eq 0 ]
  assert_valid_json "$OUT"
  printf '%s' "$OUT" | grep -q '"started":\["backend","frontend"\]'
  printf '%s' "$OUT" | grep -q '"ready":{"backend":false,"frontend":false}'
}

@test "up --json --scope none: started empty, ready empty, exit 0" {
  wt="$(add_worktree "$REPO" wt)"
  cp "$REPO/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
  cd "$wt"
  jrun up --scope none --json
  [ "$RC" -eq 0 ]
  printf '%s' "$OUT" | grep -q '"started":\[\]'
  printf '%s' "$OUT" | grep -q '"ready":{}'
}

@test "up --json ready=true when the port is accepting connections" {
  cd "$REPO"
  make_fake_ss
  PORT_TOOL=ss FAKE_PORT="$BE" jrun up backend --scope backend --json
  [ "$RC" -eq 0 ]
  assert_valid_json "$OUT"
  printf '%s' "$OUT" | grep -q '"ready":{"backend":true}'
}

@test "up --json --wait=1: exit 75, ready=false when never bound (still valid JSON)" {
  cd "$REPO"
  jrun up backend --scope backend --wait=1 --json
  [ "$RC" -eq 75 ]
  assert_valid_json "$OUT"
  printf '%s' "$OUT" | grep -q '"ready":{"backend":false}'
}

@test "up --json --wait: exit 0, ready=true when the port is up" {
  cd "$REPO"
  make_fake_ss
  PORT_TOOL=ss FAKE_PORT="$BE" jrun up backend --scope backend --wait=5 --json
  [ "$RC" -eq 0 ]
  printf '%s' "$OUT" | grep -q '"ready":{"backend":true}'
}

@test "up --json includes the per-worktree db object" {
  write_config "$REPO" \
    "FRONT_PORT_BASE=$FE" "BACK_PORT_BASE=$BE" \
    "FRONTEND_DIR='.'" "FRONTEND_CMD='true'" "BACKEND_DIR='.'" "BACKEND_CMD='true'" \
    "DB_NAME=myapp" "DB_KIND=custom" "DB_SUFFIX=_wt" "DB_AUTO_CREATE=0" \
    "DB_URL_TEMPLATE='postgres://localhost:5432/\$ATE_DB_NAME'"
  wt="$(add_worktree "$REPO" wt)"
  cp "$REPO/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
  cd "$wt"
  jrun up backend --scope backend --json
  [ "$RC" -eq 0 ]
  printf '%s' "$OUT" | grep -q '"db":{"name":"myapp_wt1","url":"postgres://localhost:5432/myapp_wt1"}'
}

@test "restart --json: stop-phase chatter stays off stdout (pure JSON)" {
  cd "$REPO"
  jrun restart backend --json
  [ "$RC" -eq 0 ]
  assert_valid_json "$OUT"
  printf '%s' "$OUT" | grep -qv '\[ate\]'
  printf '%s' "$OUT" | grep -q '"started":\["backend"\]'
}

@test "completion advertises up --json (bash + zsh)" {
  run ate completion bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -q -- '--wait --json --force'
  run ate completion zsh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q -- '--wait --json --force'
}
