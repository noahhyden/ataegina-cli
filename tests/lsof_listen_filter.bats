#!/usr/bin/env bats
# Regression: the `lsof` port backend must count only LISTENERS, not connected
# clients. `lsof -ti tcp:PORT` (no state filter) also matches ESTABLISHED sockets,
# so a browser/peer merely CONNECTED to a dev-server port would be reported as the
# port's holder — which made `ataegina down` mistake a client (chrome, gnome-shell)
# for the server and refuse to reap ataegina's own process. The fix adds
# `-sTCP:LISTEN`, matching the `ss -l` branch. (Found dogfooding on a real repo.)
#
# Hermetic: a fake `lsof` on PATH emulates real lsof — it reveals a client pid ONLY
# when called without -sTCP:LISTEN, and a listener pid either way. Driven through
# `status`/`doctor`, which run the whole ate_port_listening / ate_port_pids chain.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  BIN="$ATE_TMP/bin"; mkdir -p "$BIN"
  FE=57100; BE=58100
  write_config "$REPO" "FRONT_PORT_BASE=$FE" "BACK_PORT_BASE=$BE"
}
teardown() { common_teardown; }

# Fake lsof. $FAKE_LISTEN_PORT has a real listener (pid 88888, shown with or without
# the state filter). $FAKE_CLIENT_PORT has ONLY a connected client (pid 99999) and
# NO listener — real lsof shows it without -sTCP:LISTEN and hides it with it.
make_fake_lsof() {
  cat > "$BIN/lsof" <<'EOF'
#!/usr/bin/env bash
port=""; listen_only=0
for a in "$@"; do
  case "$a" in tcp:*) port="${a#tcp:}" ;; -sTCP:LISTEN) listen_only=1 ;; esac
done
out=""
case "$port" in
  "${FAKE_LISTEN_PORT:-x}") out=88888 ;;
  "${FAKE_CLIENT_PORT:-x}") [ "$listen_only" = 1 ] || out=99999 ;;
esac
# Real `lsof -t` prints matching pids and exits 0, or prints nothing and exits 1.
# ate_port_listening keys off that exit code, so the fake must mirror it.
[ -n "$out" ] && { echo "$out"; exit 0; }
exit 1
EOF
  chmod +x "$BIN/lsof"
}

run_ate() {
  make_fake_lsof
  run env PATH="$BIN:$PATH" ATE_PORT_TOOL=lsof \
    FAKE_LISTEN_PORT="${FAKE_LISTEN_PORT:-}" FAKE_CLIENT_PORT="${FAKE_CLIENT_PORT:-}" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    bash "$ATE_SCRIPT" "$@"
}

@test "status: a port with only a connected CLIENT reads as stopped (not the client)" {
  cd "$REPO"
  FAKE_CLIENT_PORT="$BE" run_ate status --json
  [ "$status" -eq 0 ]
  # The client pid 99999 must NOT be reported as holding the backend port.
  echo "$output" | grep -q '"backend":{"port":58100,"url":"http://localhost:58100","state":"stopped","pid":null}'
  echo "$output" | grep -qv '99999'
}

@test "status: a real LISTENER is still detected (filter doesn't over-hide)" {
  cd "$REPO"
  FAKE_LISTEN_PORT="$BE" run_ate status --json
  [ "$status" -eq 0 ]
  # Listener present, no launch record of ours -> foreign, with the listener's pid.
  echo "$output" | grep -q '"backend":{"port":58100,"url":"http://localhost:58100","state":"foreign","pid":88888}'
}

@test "doctor: a port with only a connected client is reported free, not in use" {
  cd "$REPO"
  FAKE_CLIENT_PORT="$BE" run_ate doctor --json
  # backend port must read as free; the client must not be called a holder.
  echo "$output" | grep -q '"message":"backend port :58100 is free"'
  echo "$output" | grep -qv '99999'
}

@test "doctor: a real listener on the slot port is reported in use" {
  cd "$REPO"
  FAKE_LISTEN_PORT="$BE" run_ate doctor --json
  echo "$output" | grep -q 'backend port :58100 in use'
}
