#!/usr/bin/env bash
# Build a throwaway, fully-isolated playground for exercising THIS repo's ataegina
# against a real full-stack mock — the interactive companion to the automated
# integration tests in tests/. Everything lands under sandbox/.work/ (gitignored):
# an isolated registry, isolated logs, high ports, and a mock git repo whose
# "servers" are real python listeners, so `up`/`down` drive the actual detached
# process lifecycle. Your real ~/.config/ataegina and /tmp/ate-wt* are never touched.
#
# Usage:
#   bash sandbox/setup.sh          # (re)build the mock stack under sandbox/.work
#   source sandbox/.work/env.sh    # isolated env + an `ate` shell function
#   cd sandbox/.work/mock          # the primary checkout (index 0)
#   ate up && ate ports && ate down
#   cd sandbox/.work/mock-a        # a linked worktree (index 1)
#   ate up
#
# Re-run this script anytime to reset to a clean stack. `rm -rf sandbox/.work` to nuke it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ATE="$REPO_ROOT/ataegina"
WORK="$REPO_ROOT/sandbox/.work"
FRONT_BASE=39000
BACK_BASE=38000

command -v python3 >/dev/null 2>&1 || { echo "sandbox: python3 required for the mock servers" >&2; exit 1; }

# Clean slate.
rm -rf "$WORK"
mkdir -p "$WORK/state" "$WORK/logs"

# --- the mock full-stack repo --------------------------------------------------
build_repo() {
  local dir="$1"
  mkdir -p "$dir/frontend" "$dir/backend"
  git -C "$dir" init -q
  git -C "$dir" config user.email sandbox@example.com
  git -C "$dir" config user.name  "ate sandbox"
  git -C "$dir" symbolic-ref HEAD refs/heads/main

  # A real backend: bind BACKEND_PORT and echo the per-worktree DB URL it was handed.
  cat > "$dir/backend/server.py" <<'PY'
import os, http.server, socketserver
port = int(os.environ.get("BACKEND_PORT") or os.environ.get("PORT") or "0")
print(f"backend :{port} DATABASE_URL={os.environ.get('DATABASE_URL','<unset>')}", flush=True)
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(f"backend#{port} db={os.environ.get('DATABASE_URL','')}".encode())
    def log_message(self, *a): pass
socketserver.TCPServer(("127.0.0.1", port), H).serve_forever()
PY
  cat > "$dir/frontend/server.py" <<'PY'
import os, http.server, socketserver
port = int(os.environ.get("FRONTEND_PORT") or os.environ.get("PORT") or "0")
print(f"frontend :{port} api={os.environ.get('PUBLIC_API_BASE_URL','<unset>')}", flush=True)
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(f"frontend#{port}".encode())
    def log_message(self, *a): pass
socketserver.TCPServer(("127.0.0.1", port), H).serve_forever()
PY

  echo "sandbox full-stack mock" > "$dir/README.md"
  printf 'ataegina.config.sh\n' > "$dir/.gitignore"
  cat > "$dir/ataegina.config.sh" <<CFG
FRONT_PORT_BASE=$FRONT_BASE
BACK_PORT_BASE=$BACK_BASE
FRONTEND_DIR='frontend'
FRONTEND_CMD='python3 server.py'
FRONTEND_ENV='PUBLIC_API_BASE_URL=\$BACKEND_URL'
BACKEND_DIR='backend'
BACKEND_CMD='python3 server.py'
DB_NAME='$WORK/data/shop'
DB_KIND='sqlite'
DB_SUFFIX='_wt'
DB_URL_TEMPLATE='sqlite:///\$ATE_DB_NAME.db'
CFG
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "init sandbox stack"
}

echo "[sandbox] building mock stack under $WORK"
mkdir -p "$WORK/data"
build_repo "$WORK/mock"
# The config is gitignored, so linked worktrees inherit it via the primary-config
# fallback (see load_config) — no copy needed. Add two worktrees.
git -C "$WORK/mock" worktree add -q -b feat-a "$WORK/mock-a"
git -C "$WORK/mock" worktree add -q -b feat-b "$WORK/mock-b"

# --- the isolated environment --------------------------------------------------
cat > "$WORK/env.sh" <<ENV
# Source me: isolated ataegina env for the sandbox. Nothing here touches your real
# ~/.config/ataegina or /tmp/ate-wt* — registry, logs, and ports are all sandboxed.
export ATE_REGISTRY_DIR="$WORK/state"
export LOG_DIR_BASE="$WORK/logs/ate-wt"
export FRONT_PORT_BASE=$FRONT_BASE
export BACK_PORT_BASE=$BACK_BASE
# Real port detection (lsof/ss) is used if present; leave ATE_PORT_TOOL unset for auto.
ate() { bash "$ATE" "\$@"; }
echo "[sandbox] ate -> $ATE (\$(bash "$ATE" --version))"
echo "[sandbox] registry=$WORK/state  logs=$WORK/logs  ports fe:$FRONT_BASE be:$BACK_BASE"
ENV

cat <<EOF
[sandbox] ready.

  source sandbox/.work/env.sh
  cd sandbox/.work/mock       # primary (index 0): ports $FRONT_BASE / $BACK_BASE, DB shop
  ate up && ate ports
  curl -s localhost:$BACK_BASE ; echo
  ate down

  cd sandbox/.work/mock-a     # worktree (index 1): ports $((FRONT_BASE+1)) / $((BACK_BASE+1)), DB shop_wt1
  ate up

Worktrees: mock (primary), mock-a, mock-b. Reset with: bash sandbox/setup.sh
Nuke:      rm -rf sandbox/.work
EOF
