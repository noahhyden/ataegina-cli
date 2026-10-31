#!/usr/bin/env bash
# Parametrized fake dev server (wrapper + workers + python3 listener) driven by MOCK_* env knobs, one property at a time; see the code below.
set -u

TAG="${MOCK_TAG:-mocksrv}"
PORT_TO_BIND="${MOCK_PORT:-${PORT:-${BACKEND_PORT:-0}}}"
EXIT_CODE="${MOCK_EXIT_CODE:-1}"

log() { printf '%s %s\n' "$TAG" "$*"; }

# Record env vars first, before anything can crash, so env-injection assertions never depend on binding.
if [ -n "${MOCK_ENV_OUT:-}" ]; then
  {
    printf 'BACKEND_URL=%s\n'   "${BACKEND_URL:-}"
    printf 'FRONTEND_URL=%s\n'  "${FRONTEND_URL:-}"
    printf 'PORT=%s\n'          "${PORT:-}"
    printf 'BACKEND_PORT=%s\n'  "${BACKEND_PORT:-}"
    printf 'FRONTEND_PORT=%s\n' "${FRONTEND_PORT:-}"
    printf 'ATE_INDEX=%s\n'     "${ATE_INDEX:-}"
    printf 'MOCK_CUSTOM=%s\n'   "${MOCK_CUSTOM:-}"
  } > "$MOCK_ENV_OUT" 2>/dev/null || true
fi

log "start pid=$$ port=$PORT_TO_BIND bind=${MOCK_BIND:-1}"

# Immediate crash before binding: readiness must report FAILED, not 'still starting'.
if [ "${MOCK_CRASH:-0}" = "1" ]; then
  log "crashing on purpose with code $EXIT_CODE"
  exit "$EXIT_CODE"
fi

# Ignore SIGTERM so `down` must escalate to SIGKILL (which cannot be caught).
if [ "${MOCK_IGNORE_SIGTERM:-0}" = "1" ]; then
  trap 'log "ignoring SIGTERM"' TERM
fi

# Worker child that never touches the port; it leaked on every up/down cycle when teardown only killed the port holder.
spawn_worker() {
  local n="$1"
  if [ "${MOCK_GRANDCHILD:-0}" = "1" ]; then
    (
      ( exec -a "${TAG}-grandchild-${n}" sleep 100000 ) &   # child OF the worker
      exec -a "${TAG}-worker-${n}" sleep 100000
    ) &
    log "worker+grandchild $n pid=$!"
  else
    ( exec -a "${TAG}-worker-${n}" sleep 100000 ) &
    log "worker $n pid=$!"
  fi
}

i=1
while [ "$i" -le "${MOCK_CHILDREN:-0}" ]; do
  spawn_worker "$i"
  i=$((i + 1))
done

# Simulate a slow first boot before the port opens.
if [ "${MOCK_BOOT_DELAY:-0}" != "0" ]; then
  log "boot delay ${MOCK_BOOT_DELAY}s"
  sleep "${MOCK_BOOT_DELAY}"
fi

# The listener is a python3 child so the wrapper is NOT the port holder; with binding off it just idles.
if [ "${MOCK_BIND:-1}" = "1" ] && [ "$PORT_TO_BIND" != "0" ]; then
  python3 - "$PORT_TO_BIND" "$TAG" <<'PY' &
import socket, sys, time, os
port = int(sys.argv[1])
# Optional delay BEFORE binding, independent of the wrapper's lifetime. Lets a test
# make the wrapper exit before the child binds (a daemonize-style launcher) in a
# deterministic way, to probe ataegina's readiness reporting.
d = float(os.environ.get("MOCK_LISTENER_BIND_DELAY", "0") or "0")
if d:
    time.sleep(d)
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port))
s.listen(16)
while True:
    time.sleep(1)
PY
  LISTENER=$!
  log "listener pid=$LISTENER on :$PORT_TO_BIND"

  # Abandon the listener: the wrapper exits while the port holder lives on, so `down` must reap via the port.
  if [ "${MOCK_WRAPPER_EXITS:-0}" = "1" ]; then
    # Default 1s so the listener binds first; MOCK_WRAPPER_EXIT_DELAY=0 races the wrapper's death against the bind.
    sleep "${MOCK_WRAPPER_EXIT_DELAY:-1}"
    log "wrapper exiting; orphaned listener $LISTENER keeps :$PORT_TO_BIND"
    exit 0
  fi
fi

# Voluntary exit after a while (flaky-server simulation).
if [ "${MOCK_EXIT_AFTER:-0}" != "0" ]; then
  sleep "${MOCK_EXIT_AFTER}"
  log "exiting after ${MOCK_EXIT_AFTER}s with code $EXIT_CODE"
  exit "$EXIT_CODE"
fi

# Stay alive so ataegina has a live tree to inspect and tear down.
while true; do
  sleep 1
done
