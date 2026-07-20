#!/usr/bin/env bats
# `ataegina doctor --json` — structured, machine-readable diagnostics.
#
# Spec (docs/design/agent-native.md): --json emits {status, summary:{ok,warn,fail},
# checks:[{level,message}]} on stdout, with all human [ok]/[warn]/[fail] lines and
# urls/hook chatter routed to stderr. `status` mirrors the exit code (fail iff a
# hard [fail] occurred). The dok/dwarn/dfail helpers record each row, so a
# config-defined ate_doctor hook is captured too — and a hook calling dfail flips
# status to fail and the exit code nonzero. Read-only; still a CI/agent gate.
#
# Hermetic: ATE_PORT_TOOL=none, temp registry. python3 validates the JSON when
# present. stdout/stderr are captured separately to prove stdout is pure JSON.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
}
teardown() { common_teardown; }

assert_valid_json() {
  command -v python3 >/dev/null 2>&1 || return 0
  printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)'
}
# .status / .summary.<k> accessors (python3), skipped when python3 is absent.
jget() { command -v python3 >/dev/null 2>&1 || return 0; printf '%s' "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); print($2)"; }

# Capture stdout in $OUT, stderr in $ERR, exit code in $RC (tolerates nonzero).
drun() {
  local errf; errf="$(mktemp)"
  OUT="$(ATE_PORT_TOOL="${ATE_PORT_TOOL:-none}" ATE_REGISTRY_DIR="$ATE_TMP/registry" \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" bash "$ATE_SCRIPT" "$@" 2>"$errf")" && RC=0 || RC=$?
  ERR="$(cat "$errf")"; rm -f "$errf"
}

@test "doctor --json: stdout is pure JSON, human lines on stderr, exit 0" {
  cd "$REPO"
  drun doctor --json
  [ "$RC" -eq 0 ]
  assert_valid_json "$OUT"
  printf '%s' "$OUT" | grep -qv '\[ok\]'      # no human check lines on stdout
  printf '%s' "$ERR" | grep -q '\[ok\]'         # they went to stderr
  [ "$(jget "$OUT" 'd["status"]')" = pass ]
}

@test "doctor --json: summary counts and checks array are present" {
  cd "$REPO"
  drun doctor --json
  [ "$RC" -eq 0 ]
  # A healthy hermetic run has several ok checks and at least one warn (port tool
  # is 'none', and the launcher is not on PATH under a relative invocation).
  if command -v python3 >/dev/null 2>&1; then
    [ "$(jget "$OUT" 'd["summary"]["ok"]')" -ge 1 ]
    [ "$(jget "$OUT" 'd["summary"]["warn"]')" -ge 1 ]
    [ "$(jget "$OUT" 'd["summary"]["fail"]')" -eq 0 ]
    [ "$(jget "$OUT" 'len(d["checks"])')" -ge 5 ]
    # summary counts equal the number of checks.
    [ "$(jget "$OUT" 'd["summary"]["ok"]+d["summary"]["warn"]+d["summary"]["fail"]')" -eq "$(jget "$OUT" 'len(d["checks"])')" ]
  fi
  printf '%s' "$OUT" | grep -q '"level":"ok","message":"worktree: index #0'
}

@test "doctor --json: 'none' port tool is recorded as a warn check" {
  cd "$REPO"
  drun doctor --json
  printf '%s' "$OUT" | grep -q '"level":"warn","message":"port tool: none'
}

@test "doctor --json: a config ate_doctor hook that fails flips status + exit code" {
  write_config "$REPO" \
    "ate_doctor() { dok 'sidecar reachable'; dfail 'migrations are behind'; }"
  cd "$REPO"
  drun doctor --json
  [ "$RC" -ne 0 ]
  assert_valid_json "$OUT"
  [ "$(jget "$OUT" 'd["status"]')" = fail ]
  if command -v python3 >/dev/null 2>&1; then
    [ "$(jget "$OUT" 'd["summary"]["fail"]')" -ge 1 ]
  fi
  # The hook's own dok/dfail rows are captured in the report.
  printf '%s' "$OUT" | grep -q '"level":"fail","message":"migrations are behind"'
  printf '%s' "$OUT" | grep -q '"level":"ok","message":"sidecar reachable"'
}

@test "doctor (no --json) is unchanged: human lines on stdout, exit 0" {
  cd "$REPO"
  run ate doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\[ok\]   worktree: index #0'
  echo "$output" | grep -qv '"checks"'
}

@test "doctor rejects an unknown argument (exit 2)" {
  cd "$REPO"
  run ate doctor --bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "unknown argument"
}

@test "completion advertises doctor --json (bash + zsh)" {
  run ate completion bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '[ (|]doctor[|)].*--json'
  run ate completion zsh
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '[ (|]doctor[|)].*compadd -- --json'
}
