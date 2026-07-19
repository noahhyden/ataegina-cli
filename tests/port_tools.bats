#!/usr/bin/env bats
# Port-backend variants (ate_port_tool / ate_port_listening / ate_port_pids /
# ate_port_proc_desc / _ate_proc_listening). The rest of the suite only ever uses
# `none` or `lsof`; this drives the ss / fuser / proc branches with fake `ss`/`fuser`
# stubs on PATH (deterministic, no real sockets) and the proc branch against the real
# /proc/net/tcp with a real listener. Exercised through `ate doctor`, which calls the
# whole chain via doctor_port_check.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  BIN="$ATE_TMP/bin"; mkdir -p "$BIN"
  # A high, fixed backend slot so the fake tools have a known port to "hold".
  BE=51900; FE=52900
  write_config "$REPO" "FRONT_PORT_BASE=$FE" "BACK_PORT_BASE=$BE" "BACKEND_DIR='.'" "BACKEND_CMD='true'"
}
teardown() { common_teardown; }

# Fake `ss`: reports $FAKE_PORT as a LISTEN socket. Honors -p (adds a pid) and the
# -H/no-H split ate uses; FAKE_SS_NO_H=1 makes -H fail so the fallback path runs.
make_fake_ss() {
  cat > "$BIN/ss" <<'EOF'
#!/usr/bin/env bash
# ataegina passes BUNDLED flags (-ltnH / -ltnpH / -ltn); parse the bundle, not "-p".
want="${FAKE_PORT:-0}"; flags=""; query=""
for a in "$@"; do case "$a" in -*) flags="$flags$a" ;; *) query="$query $a" ;; esac; done
case "$query" in *"sport = :$want"*) : ;; *) exit 0 ;; esac
case "$flags" in *H*) [ "${FAKE_SS_NO_H:-0}" = 1 ] && exit 2 ;; esac
case "$flags" in *H*) : ;; *) echo "State Recv-Q Send-Q Local:Port Peer Process" ;; esac
case "$flags" in
  *p*) echo "LISTEN 0 128 127.0.0.1:$want 0.0.0.0:* users:((\"fakesrv\",pid=4242,fd=7))" ;;
  *)   echo "LISTEN 0 128 127.0.0.1:$want 0.0.0.0:*" ;;
esac
EOF
  chmod +x "$BIN/ss"
}
make_fake_fuser() {
  cat > "$BIN/fuser" <<'EOF'
#!/usr/bin/env bash
# fuser PORT/tcp -> pids on stdout for our FAKE_PORT.
case "$1" in "${FAKE_PORT:-0}/tcp") echo "  4242" ;; *) exit 1 ;; esac
EOF
  chmod +x "$BIN/fuser"
}
doctor() {
  run env PATH="$BIN:$PATH" "$@" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" doctor
}

make_fake_lsof() {
  cat > "$BIN/lsof" <<'EOF'
#!/usr/bin/env bash
# fake lsof: `lsof -ti tcp:PORT` -> a pid for our FAKE_PORT, nothing otherwise.
p=""; for a in "$@"; do case "$a" in tcp:*) p="${a#tcp:}" ;; esac; done
[ "$p" = "${FAKE_PORT:-0}" ] && echo 4242
EOF
  chmod +x "$BIN/lsof"
}

@test "lsof backend: doctor reports the slot in use via lsof (deterministic, fake)" {
  make_fake_lsof
  cd "$REPO"
  doctor ATE_PORT_TOOL=lsof FAKE_PORT="$BE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "port tool: lsof"
  echo "$output" | grep -qi "backend port :$BE in use"
  echo "$output" | grep -q "pid 4242"
}

@test "ss backend: doctor reports the slot in use, with the pid from ss -p" {
  make_fake_ss
  cd "$REPO"
  doctor ATE_PORT_TOOL=ss FAKE_PORT="$BE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "port tool: ss"
  echo "$output" | grep -qi "backend port :$BE in use"
  echo "$output" | grep -q "pid 4242"
}

@test "ss backend: the -H-rejected fallback path still detects the listener" {
  make_fake_ss
  cd "$REPO"
  doctor ATE_PORT_TOOL=ss FAKE_PORT="$BE" FAKE_SS_NO_H=1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "backend port :$BE in use"
}

@test "fuser backend: doctor reports the slot in use via fuser" {
  make_fake_fuser
  cd "$REPO"
  doctor ATE_PORT_TOOL=fuser FAKE_PORT="$BE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "port tool: fuser"
  echo "$output" | grep -qi "backend port :$BE in use"
  echo "$output" | grep -q "4242"
}

@test "proc backend: /proc/net/tcp detects a real listener (pid unknown)" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  [ -r /proc/net/tcp ] || skip "/proc/net/tcp not readable"
  # A real listener on the backend slot so _ate_proc_listening finds state 0A.
  python3 - "$BE" <<'PY' &
import socket,sys,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(("127.0.0.1",int(sys.argv[1]))); s.listen(8)
while True: time.sleep(1)
PY
  local lp=$!
  local i=0; while [ "$i" -lt 40 ]; do (exec 3<>/dev/tcp/127.0.0.1/$BE) 2>/dev/null && break; sleep 0.1; i=$((i+1)); done
  cd "$REPO"
  doctor ATE_PORT_TOOL=proc
  kill "$lp" 2>/dev/null || true
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "backend port :$BE in use"
  echo "$output" | grep -qi "pid unknown"
}

@test "doctor with port tool none warns that checks are degraded" {
  cd "$REPO"
  doctor ATE_PORT_TOOL=none
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "port tool: none"
  echo "$output" | grep -qi "port checks degraded"
  # none can't see sockets, so the slot reads as free.
  echo "$output" | grep -qi "backend port :$BE is free"
}

@test "an override for a tool that is not installed falls back to auto-detect" {
  # Ask for fuser but do NOT provide it; ate_port_tool must fall through to detect.
  cd "$REPO"
  doctor ATE_PORT_TOOL=fuser
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE "port tool: (lsof|ss|fuser|proc|none)"
}
