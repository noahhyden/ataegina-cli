#!/usr/bin/env bats
# `ataegina status [--json]` — READ-ONLY per-surface liveness for this worktree.
#
# Spec (docs/design/agent-native.md): the side-effect-free "is my stack up, and
# where?" query. Per surface: running (a live server we launched holds the port),
# foreign (something we did not launch holds it), unknown (held but ownership
# unverifiable), or stopped (nothing on the port). --json folds state+pid into the
# frontend/backend sub-objects of the shared slot shape. Never mutates; exit 0
# regardless of state.
#
# Hermetic. stopped runs under ATE_PORT_TOOL=none. foreign/unknown use a fake `ss`
# on PATH that reports the derived backend port LISTEN with a pid (no real socket):
# foreign = no launch record for the port; unknown = a launch record whose recorded
# pid is dead. The running (ours) state needs a real owned process -> integration.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  BIN="$ATE_TMP/bin"; mkdir -p "$BIN"
  BE=54100; FE=53100
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

# Fake `ss` reporting $FAKE_PORT as LISTEN, with a pid under -p (as ate_port_pids
# needs). Same shape as tests/port_tools.bats.
make_fake_ss() {
  cat > "$BIN/ss" <<'EOF'
#!/usr/bin/env bash
want="${FAKE_PORT:-0}"; flags=""; query=""
for a in "$@"; do case "$a" in -*) flags="$flags$a" ;; *) query="$query $a" ;; esac; done
case "$query" in *"sport = :$want"*) : ;; *) exit 0 ;; esac
case "$flags" in
  *p*) echo "LISTEN 0 128 127.0.0.1:$want 0.0.0.0:* users:((\"fakesrv\",pid=4242,fd=7))" ;;
  *)   echo "LISTEN 0 128 127.0.0.1:$want 0.0.0.0:*" ;;
esac
EOF
  chmod +x "$BIN/ss"
}

status_ss() {
  make_fake_ss
  run env PATH="$BIN:$PATH" ATE_PORT_TOOL=ss FAKE_PORT="$BE" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" "$@"
}

@test "status (human) reports stopped surfaces for an idle primary" {
  cd "$REPO"
  run ate status
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'frontend +:53100 +stopped'
  echo "$output" | grep -qE 'backend +:54100 +stopped'
}

@test "status --json: stopped surfaces, null pids, one valid JSON line" {
  cd "$REPO"
  run ate status --json
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"frontend":{"port":53100,"url":"http://localhost:53100","state":"stopped","pid":null}'
  echo "$output" | grep -q '"backend":{"port":54100,"url":"http://localhost:54100","state":"stopped","pid":null}'
}

@test "status --json: a port held with no launch record is 'foreign' (with pid)" {
  cd "$REPO"
  status_ss status --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"backend":{"port":54100,"url":"http://localhost:54100","state":"foreign","pid":4242}'
}

@test "status --json: a held port whose recorded launch pid is dead is 'unknown'" {
  cd "$REPO"
  # Fabricate a launch record for the backend with a pid that is not alive.
  local logdir="$ATE_TMP/logs/ate-wt0"
  mkdir -p "$logdir"
  echo 999999 > "$logdir/backend.pid"
  status_ss status --json
  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | grep -q '"backend":{"port":54100,"url":"http://localhost:54100","state":"unknown","pid":4242}'
}

@test "status --json includes the per-worktree db object when configured" {
  write_config "$REPO" "${DBCFG[@]}"
  wt="$(add_worktree "$REPO" wtA)"
  cd "$wt"
  run ate status --json
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"db":{"name":"myapp_wt1","url":"postgres://localhost:5432/myapp_wt1"}'
}

@test "status --json reflects a linked worktree's own index and ports" {
  wt="$(add_worktree "$REPO" wtA)"
  cd "$wt"
  run ate status --json
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"index":1,'
  echo "$output" | grep -q '"frontend":{"port":53101,'
  echo "$output" | grep -q '"backend":{"port":54101,'
}

@test "status is read-only: it does not create the log dir (unlike up)" {
  cd "$REPO"
  run ate status
  [ "$status" -eq 0 ]
  [ ! -d "$ATE_TMP/logs/ate-wt0" ]
}

@test "status rejects an unknown argument (exit 2)" {
  cd "$REPO"
  run ate status --bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "unknown argument"
}

@test "completion advertises status --json (bash + zsh)" {
  run ate completion bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ports|status) COMPREPLY=.*--json'
  run ate completion zsh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ports|status) compadd -- --json'
}

@test "status --json: a server WE launched is reported 'running' (real process)" {
  integration_only
  local repo be tool
  repo="$(make_repo "$ATE_TMP/rt")"
  be=54800
  # A real backend that binds its derived port (from $BACKEND_PORT) and holds it.
  cat > "$repo/server.py" <<'PY'
import os, socket, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(os.environ["BACKEND_PORT"])))
s.listen()
time.sleep(30)
PY
  write_config "$repo" "FRONT_PORT_BASE=53800" "BACK_PORT_BASE=$be" \
    "BACKEND_DIR='.'" "BACKEND_CMD='python3 server.py'"
  cd "$repo"
  if command -v lsof >/dev/null 2>&1; then tool=lsof
  elif command -v ss >/dev/null 2>&1; then tool=ss
  else skip "no lsof/ss to observe a real socket"; fi
  ATE_PORT_TOOL="$tool" ate up backend --scope backend --wait=15 >/dev/null 2>&1
  run env ATE_PORT_TOOL="$tool" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" status --json
  ATE_PORT_TOOL="$tool" ate down backend >/dev/null 2>&1 || true
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"backend":{"port":54800,"url":"http://localhost:54800","state":"running"'
}
