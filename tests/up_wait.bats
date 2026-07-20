#!/usr/bin/env bats
# `ataegina up --wait[=SECONDS]` — the readiness CONTRACT for agents.
#
# Spec (docs/design/agent-native.md): with --wait, `up` blocks until every server
# it launched is accepting connections (up to SECONDS, default 60 / ATE_UP_WAIT),
# then exits 75 if any is not ready by the deadline; exits 0 when everything
# launched is ready (or nothing was launched). Without --wait, behavior is
# unchanged (fire-and-forget, always exit 0). This is what lets an agent write
# `ataegina up --wait && curl "$BACKEND_URL/health"` with no hand-rolled poll.
#
# Hermetic. The not-ready path runs under ATE_PORT_TOOL=none (nothing ever binds),
# with a `true` backend (instant exit — no lingering process). The ready path uses
# a fake `ss` on PATH that reports the derived backend port as LISTEN, so no real
# socket is opened. Fixed high port bases so the fake tool has a known port.

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

# Fake `ss` reporting $FAKE_PORT as a LISTEN socket (deterministic, no real socket).
# Same shape as tests/port_tools.bats: parse the bundled flags, match the sport query.
make_fake_ss() {
  cat > "$BIN/ss" <<'EOF'
#!/usr/bin/env bash
want="${FAKE_PORT:-0}"; query=""
for a in "$@"; do case "$a" in -*) : ;; *) query="$query $a" ;; esac; done
case "$query" in *"sport = :$want"*) echo "LISTEN 0 128 127.0.0.1:$want 0.0.0.0:*" ;; *) exit 0 ;; esac
EOF
  chmod +x "$BIN/ss"
}

# Run `up` in this tree under the fake port tool (ss) with the backend "listening".
up_ss_listening() {
  make_fake_ss
  run env PATH="$BIN:$PATH" ATE_PORT_TOOL=ss FAKE_PORT="$BE" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" "$@"
}

@test "up --wait=1 exits 75 when the launched backend never binds" {
  cd "$REPO"
  run ate up backend --scope backend --wait=1
  [ "$status" -eq 75 ]
  echo "$output" | grep -q "NOT ready after 1s"
}

@test "up --wait (bare) honors ATE_UP_WAIT for the timeout" {
  cd "$REPO"
  ATE_UP_WAIT=1 run ate up backend --scope backend --wait
  [ "$status" -eq 75 ]
  echo "$output" | grep -q "NOT ready after 1s"
}

@test "up --wait exits 0 and reports 'ready' when the port is accepting connections" {
  cd "$REPO"
  up_ss_listening up backend --scope backend --wait
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "backend ready ->"
}

@test "up --wait=0 requires the port ready immediately (0 -> ready, else 75)" {
  cd "$REPO"
  # Nothing listening: an immediate deadline fails.
  run ate up backend --scope backend --wait=0
  [ "$status" -eq 75 ]
  # Listening: an immediate deadline passes.
  up_ss_listening up backend --scope backend --wait=0
  [ "$status" -eq 0 ]
}

@test "up --scope none --wait exits 0 (nothing launched is trivially ready)" {
  wt="$(add_worktree "$REPO" wt)"
  cp "$REPO/ataegina.config.sh" "$ATE_TMP/registry/ataegina.config.sh"
  cd "$wt"
  run ate up --scope none --wait=1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "NOT ready"
}

@test "up --wait with a non-integer value errors (exit 2)" {
  cd "$REPO"
  run ate up backend --scope backend --wait=abc
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "non-negative integer"
}

@test "up --wait with a negative value errors (exit 2)" {
  cd "$REPO"
  run ate up backend --scope backend --wait=-3
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "non-negative integer"
}

@test "up (no --wait) is unchanged: exits 0 and never says 'NOT ready'" {
  cd "$REPO"
  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "NOT ready"
}

@test "restart --wait propagates the readiness exit code (75 when not ready)" {
  cd "$REPO"
  run ate restart backend --wait=1
  [ "$status" -eq 75 ]
  echo "$output" | grep -q "NOT ready after 1s"
}

@test "completion advertises up --wait (bash + zsh)" {
  run ate completion bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -q -- '--scope --wait --json --force'
  run ate completion zsh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q -- '--scope --wait --json --force'
}
