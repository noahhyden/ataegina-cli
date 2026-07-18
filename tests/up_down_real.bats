#!/usr/bin/env bats
# Real up/down lifecycle with ACTUAL server processes (the unit suite otherwise
# forces ATE_PORT_TOOL=none and starts nothing). Covers python and node backends:
# `up` must launch the server on the derived port and it must really be listening;
# the injected env (BACKEND_URL + a custom BACKEND_ENV) must reach the live process;
# `down` must free the port. Uses a real port tool and high, obscure port bases.

load helper

# Unique markers so teardown can always reap, and so `pgrep`/detection are precise.
PYMARK="ate_real_py_5f3a1"
NODEMARK="ate_real_node_5f3a1"

setup() {
  common_setup
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  # A real port tool (helper defaults to none, which can't see real sockets).
  if command -v lsof >/dev/null 2>&1; then export ATE_PORT_TOOL=lsof
  elif command -v ss >/dev/null 2>&1; then export ATE_PORT_TOOL=ss
  else skip "no port tool (lsof/ss) available"; fi
}
teardown() {
  pkill -f "$PYMARK" 2>/dev/null || true
  pkill -f "$NODEMARK" 2>/dev/null || true
  common_teardown
}

# Is something listening on TCP $1? (independent of ataegina's own detection).
listening() {
  if command -v lsof >/dev/null 2>&1; then lsof -ti tcp:"$1" >/dev/null 2>&1
  else ss -ltn "sport = :$1" 2>/dev/null | grep -q ":$1"; fi
}
wait_listening() { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" && return 0; sleep 0.25; i=$((i+1)); done; return 1; }
wait_free()      { local p="$1" i=0; while [ "$i" -lt 40 ]; do listening "$p" || return 0; sleep 0.25; i=$((i+1)); done; return 1; }

@test "real up/down: python backend binds the derived port, down frees it" {
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  cat > "$repo/pyserver.py" <<PY
import os, socket, time  # $PYMARK
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(os.environ["BACKEND_PORT"])))
s.listen(16)
while True: time.sleep(1)
PY
  write_config "$repo" "FRONT_PORT_BASE=46000" "BACK_PORT_BASE=47000" \
    "BACKEND_DIR='.'" "BACKEND_CMD='python3 pyserver.py'"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening 47000    # primary index 0 -> 47000+0
  ate down backend
  wait_free 47000
}

@test "real up/down: node backend binds the derived port, down frees it" {
  command -v node >/dev/null 2>&1 || skip "node required"
  local repo
  repo="$(make_repo "$ATE_TMP/repo")"
  cat > "$repo/nodeserver.js" <<JS
// $NODEMARK
require("net").createServer().listen(process.env.BACKEND_PORT, "127.0.0.1");
setInterval(() => {}, 1000);
JS
  write_config "$repo" "FRONT_PORT_BASE=46000" "BACK_PORT_BASE=47000" \
    "BACKEND_DIR='.'" "BACKEND_CMD='node nodeserver.js'"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening 47000
  ate down backend
  wait_free 47000
}

@test "real up: BACKEND_URL and a custom BACKEND_ENV reach the live process" {
  local repo out
  repo="$(make_repo "$ATE_TMP/repo")"
  out="$ATE_TMP/env.out"
  cat > "$repo/pyserver.py" <<PY
import os, socket, time  # $PYMARK
with open(os.environ["ATE_ENV_OUT"], "w") as f:
    f.write("BACKEND_URL=%s\n" % os.environ.get("BACKEND_URL", ""))
    f.write("MY_CUSTOM=%s\n"   % os.environ.get("MY_CUSTOM", ""))
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(os.environ["BACKEND_PORT"])))
s.listen(16)
while True: time.sleep(1)
PY
  write_config "$repo" "FRONT_PORT_BASE=46000" "BACK_PORT_BASE=47000" \
    "BACKEND_DIR='.'" "BACKEND_CMD='python3 pyserver.py'" \
    "BACKEND_ENV='ATE_ENV_OUT=$out; MY_CUSTOM=custom_\$BACKEND_PORT'"
  cd "$repo"

  run ate up backend --scope backend
  [ "$status" -eq 0 ]
  wait_listening 47000
  ate down backend >/dev/null 2>&1 || true

  [ -f "$out" ]
  grep -q "BACKEND_URL=http://localhost:47000" "$out"
  grep -q "MY_CUSTOM=custom_47000" "$out"
}
