#!/usr/bin/env bash
# mockserver.sh — a parametrized FAKE dev server for probing ataegina's process,
# port, signal, and readiness handling under conditions that are hard to trigger
# reliably with a real framework's dev server (slow boot, immediate crash, worker
# trees that never hold the socket, a process that ignores SIGTERM, a process that
# outlives its launch wrapper, etc.).
#
# Everything is env-driven so a test can dial exactly ONE property at a time and
# assert ataegina's reaction. This is the "fake tool with special properties" the
# harness is built around: change a knob, observe a behavioral change, find bugs.
#
# It is deliberately close in shape to a real dev server: a bash wrapper (this
# process, the one ataegina records as the launch pid) that may fork worker
# children and a python3 socket listener. That mirrors uvicorn --reload, next dev,
# vite, etc., where the port holder is NOT the recorded wrapper pid — the exact
# case ataegina's tree-reaping and pid tracking exist for.
#
# Dependency: python3 for the actual TCP listen (already required by the
# integration tier). Everything else is pure bash 3.2.
#
# Knobs (all optional; sane defaults make it a plain, healthy server):
#   MOCK_PORT          port to bind. Default: $PORT, else $BACKEND_PORT, else 0 (none).
#   MOCK_BIND          1 = bind the port (default). 0 = never bind (worker-only server).
#   MOCK_BOOT_DELAY    seconds to sleep BEFORE binding (simulate slow first compile).
#   MOCK_CRASH         1 = exit immediately without binding (simulate a broken command).
#   MOCK_EXIT_CODE     exit code used by MOCK_CRASH and MOCK_EXIT_AFTER. Default 1.
#   MOCK_EXIT_AFTER    seconds to run, then exit voluntarily (simulate a flaky server).
#   MOCK_CHILDREN      number of worker children to fork that DO NOT hold the port
#                      (exercise tree reaping — orphan-leak detection).
#   MOCK_GRANDCHILD    1 = each worker child forks its own child (deeper tree).
#   MOCK_IGNORE_SIGTERM 1 = trap and IGNORE SIGTERM (force ataegina to escalate to KILL).
#   MOCK_WRAPPER_EXITS 1 = after the listener binds, the WRAPPER exits 0, leaving the
#                      listener orphaned and still holding the port. Exercises down's
#                      port-holder path when the RECORDED launch pid is already dead.
#   MOCK_WRAPPER_EXIT_DELAY seconds the wrapper waits after launching the listener
#                      before it exits (default 1; used with MOCK_WRAPPER_EXITS).
#   MOCK_LISTENER_BIND_DELAY seconds the LISTENER waits before binding the port,
#                      independent of the wrapper's lifetime. With MOCK_WRAPPER_EXITS
#                      + a 0 exit delay this makes the wrapper die BEFORE the child
#                      binds — a daemonize-style launcher — to probe readiness.
#   MOCK_TAG           marker string echoed to the log + used in child arg names so
#                      teardown/pgrep can find every descendant. Default: mocksrv.
#   MOCK_ENV_OUT       if set, write a few observed env vars to this file then continue
#                      (lets a test assert injected env reached the live process).
#
# Usage in a config:  BACKEND_CMD='bash tests/fake/mockserver.sh'
set -u

TAG="${MOCK_TAG:-mocksrv}"
PORT_TO_BIND="${MOCK_PORT:-${PORT:-${BACKEND_PORT:-0}}}"
EXIT_CODE="${MOCK_EXIT_CODE:-1}"

log() { printf '%s %s\n' "$TAG" "$*"; }

# Record a few env vars if asked (before anything can crash), so env-injection
# assertions do not depend on the server ever binding.
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

# Immediate crash: exit before binding. ataegina's readiness poll should see the
# launch pid gone and report FAILED (not "still starting").
if [ "${MOCK_CRASH:-0}" = "1" ]; then
  log "crashing on purpose with code $EXIT_CODE"
  exit "$EXIT_CODE"
fi

# Optionally ignore SIGTERM so `down`'s polite kill is a no-op and it must
# escalate to SIGKILL. We still let SIGKILL through (uncatchable by design).
if [ "${MOCK_IGNORE_SIGTERM:-0}" = "1" ]; then
  trap 'log "ignoring SIGTERM"' TERM
fi

# A worker child that never touches the port. It sleeps forever under a
# recognizable arg so ps/pgrep can find it. This is the process that used to leak
# on every up/down cycle when teardown only killed the port holder.
#
# With MOCK_GRANDCHILD=1 the worker forks its OWN child FIRST and then becomes
# `sleep` via exec — so the grandchild's parent is the worker, not this wrapper.
# That yields a real 2-level tree (wrapper -> worker -> grandchild) which forces
# ataegina's ate_pid_tree BFS to actually descend; an earlier version forked the
# "grandchild" from the wrapper too, making it a sibling and testing only breadth.
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

# The listener. Kept as a child (python3) so the wrapper (this pid) is NOT the
# port holder — the realistic and harder case for teardown. If binding is off, we
# just idle so the wrapper/worker tree stays alive for teardown tests.
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

  # Abandon the listener: let it bind, then exit the wrapper so the process that
  # ataegina RECORDED at launch is dead while the port holder lives on (orphaned
  # to init). `down` must then reap it via the port, not the recorded pid.
  if [ "${MOCK_WRAPPER_EXITS:-0}" = "1" ]; then
    # Default 1s so the listener is bound before we abandon it (deterministic test);
    # set MOCK_WRAPPER_EXIT_DELAY=0 to race the wrapper's death against the bind.
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
