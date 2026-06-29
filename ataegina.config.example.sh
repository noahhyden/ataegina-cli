# ataegina.config.example.sh
#
# The fastest way to get a config is `ataegina init`, which detects your stack
# and writes a declarative ataegina.config.sh for you. This file documents what
# that config looks like (the declarative form, first) and the bash escape hatch
# for stacks the detector cannot express (defining the hook functions yourself).
#
# Copy this to `ataegina.config.sh` in your repo root (or to
# $XDG_CONFIG_HOME/ataegina/ataegina.config.sh for a machine-wide default) and
# edit it for your stack. ataegina sources this file before doing anything.
#
# You rarely need to hand-edit the scalar keys: `ataegina config set KEY VALUE`
# writes them for you (and `--global` targets the XDG copy), `ataegina config
# list` shows every key with its effective value and source, and `ataegina
# config get KEY` / `unset KEY` round it out. The hook FUNCTIONS below
# (ate_start_*, ate_doctor) are the part you still edit here by hand.
#
# Resolution order (first hit wins):
#   1. $ATE_CONFIG (explicit path)
#   2. <repo root>/ataegina.config.sh
#   3. $XDG_CONFIG_HOME/ataegina/ataegina.config.sh
#
# This file is plain bash. Keep it dependency-free.

# ---------------------------------------------------------------------------
# Tunables. Every worktree gets a stable index N; ports are derived as
# base + N, so two worktrees never collide.
# ---------------------------------------------------------------------------

# Port bases. Frontend lands on FRONT_PORT_BASE+N, backend on BACK_PORT_BASE+N.
FRONT_PORT_BASE=5173
BACK_PORT_BASE=8000

# Where per-worktree logs go. The index N is appended, e.g. /tmp/ate-wt3.
LOG_DIR_BASE=/tmp/ate-wt

# Registry root. The index registry is PER-REPO: each primary checkout gets its
# own tab-separated file (index -> worktree path) at REGISTRY_DIR/repos/<key>,
# where <key> is the primary's dir name plus a portable digest of its path, so two
# unrelated repos never collide on indices (each one's primary is index 0). Safe
# to delete (indices get reassigned). To force ONE shared file across repos, set
# the ATE_REGISTRY env var to that file's path instead.
# REGISTRY_DIR="$HOME/.config/ataegina"

# Scope-aware startup. By default `ataegina up` classifies the worktree's git
# diff into a scope (frontend / backend / both / none) and starts only what is
# needed, pointing any surface it does not run locally at the shared default
# server in the primary checkout (frontend FRONT_PORT_BASE, backend
# BACK_PORT_BASE). The primary (index 0) is always `both`. Override per run with
# `ataegina up --scope X`, or with a `scope:` line in $ATE_TASK_FILE if you set it.
# Set this to 0 to disable detection and always start `both` (the pre-scope
# behavior). See the "Scope-aware startup" section of the README.
# ATE_SCOPE_AUTO=1
#
# Base ref scope detection diffs against. Without it, the base is resolved as: the
# current branch's upstream (e.g. origin/dev), else the remote default branch
# (origin/HEAD), else the first local of main/master/develop. Set it when your
# integration branch is non-standard (e.g. prod is `main` but work merges to
# `dev`) and the auto-resolution picks the wrong one.
# ATE_BASE_BRANCH='dev'
#
# When `up` AUTO-detects scope (no --scope, no `scope:` field) and the diff is
# empty, the raw scope is `none`; rather than start nothing, `up` nudges it to
# `both` and logs a hint. An explicit `--scope none` / `scope: none` still means
# none. (No knob; documented here so the behavior is not surprising.)

# Port-detection backend. ataegina probes "is this port up / who holds it" to
# guard `up`, to kill by port on `down`, and to report holders in `doctor`. It
# auto-detects a backend in this order: lsof, ss (iproute2), fuser, then parsing
# /proc/net/tcp (Linux, listening-detection only), else none. lsof is often
# absent on minimal Debian/Ubuntu; installing lsof or iproute2 (ss) is enough.
# Force a specific backend if you must (values: lsof|ss|fuser|proc|none); an
# unavailable choice falls back to auto-detect. `ataegina doctor` prints which
# backend is active. With `none`, port checks are degraded (up still starts).
# ATE_PORT_TOOL=lsof

# Opt-in update check (default OFF). When set to 1, ataegina prints a single
# one-line notice at the END of `up` if a newer release is
# published, e.g.:
#   [ate] a newer version is available (v0.2.0); run: ataegina update
# It never runs on other commands and never blocks or delays the actual work.
# Throttled to at most once per 24h (a timestamp is kept in REGISTRY_DIR), and
# it is fully offline-safe: a short network timeout, and ANY failure (no
# network, the repo is private, a parse error) produces no output and does not
# change the command's exit status. Run `ataegina update` to self-update.
#
# Privacy: when enabled, this makes a SINGLE GET to GitHub's public releases API
# (api.github.com) to read the latest release tag. There is no other telemetry,
# no identifiers are sent, and nothing is transmitted when it is off (the
# default). The endpoint is overridable via ATE_RELEASES_URL.
# ATE_UPDATE_CHECK=0

# ---------------------------------------------------------------------------
# Declarative config (recommended). Set these and you never write any bash:
# ataegina's built-in default hooks read them, start each server in the right
# directory on this tree's port, and log into the per-tree log dir.
#
#   FRONTEND_DIR / BACKEND_DIR   directory (relative to the repo root) to cd into
#   FRONTEND_CMD / BACKEND_CMD   the command to run there. It is a string passed
#                                to `sh -c`, so it may reference the exported
#                                vars below: $FRONTEND_PORT, $BACKEND_PORT,
#                                $BACKEND_URL, etc. Keep it single-quoted so
#                                those expand at run time, not when sourced.
#   FRONTEND_ENV / BACKEND_ENV   optional extra KEY=VALUE assignments exported
#                                before the command runs. One per line, or
#                                semicolon-separated. Values may reference
#                                $BACKEND_URL etc.
#
# These vars are exported into every hook before it runs:
#
#   ATE_INDEX               this worktree's stable index N
#   REPO_ROOT               absolute path to this worktree
#   FRONTEND_PORT           FRONT_PORT_BASE + N
#   BACKEND_PORT            BACK_PORT_BASE  + N
#   PORT                    same as the relevant *_PORT (convenience)
#   BACKEND_URL             http://localhost:$BACKEND_PORT
#   FRONTEND_URL            http://localhost:$FRONTEND_PORT
#   FRONTEND_API_BASE_URL   http://localhost:$BACKEND_PORT  (same as BACKEND_URL)
#   DEV_LOG_DIR             this worktree's log dir
#   ATE_DB_NAME             this worktree's database name (only if DB_NAME is set)
# ---------------------------------------------------------------------------

# Worked example: a Next.js frontend talking to a Python (uv) backend.
FRONTEND_DIR='frontend'
FRONTEND_CMD='npx next dev -p $FRONTEND_PORT'
# Rename this to the env var your app actually reads for its API base URL
# (Next: NEXT_PUBLIC_API_BASE_URL, Vite: VITE_API_URL, CRA: REACT_APP_API_URL).
FRONTEND_ENV='NEXT_PUBLIC_API_BASE_URL=$BACKEND_URL'

BACKEND_DIR='backend'
BACKEND_CMD='uv run uvicorn main:app --port $BACKEND_PORT'
# BACKEND_ENV='LOG_LEVEL=debug'

# ---------------------------------------------------------------------------
# Per-worktree databases (optional; OFF unless DB_NAME is set). Running many
# worktrees as live stacks collides on PORTS *and* on the DATABASE — parallel
# agents stomp each other's schema and data through a shared dev DB. Set DB_NAME
# and ataegina derives a separate database per worktree, injects its connection
# string, and (on `up`) creates it. The PRIMARY (index 0) keeps the unsuffixed
# DB_NAME (your shared dev DB); each worktree N>0 gets DB_NAME + DB_SUFFIX + N
# (e.g. myapp_wt3). Inspect/manage with `ataegina db [name|url|create|drop]`.
# `down` never drops a DB, so your data persists across restarts.
#
# DB_NAME=myapp                              # set this to enable the feature
# DB_KIND=postgres                           # postgres | mysql | sqlite | custom
# DB_SUFFIX=_wt                              # worktree DB = DB_NAME + DB_SUFFIX + N
# DB_URL_TEMPLATE='postgres://localhost:5432/$ATE_DB_NAME'   # expanded per tree
# DB_URL_VAR=DATABASE_URL                    # env var the URL is injected into
# DB_AUTO_CREATE=1                           # `up` ensures the worktree DB exists
#
# Defaults per DB_KIND use the standard CLIs (createdb/dropdb, mysql, a sqlite
# file). Override them, or point them at a managed provider (Neon / PlanetScale /
# Turso branches) — $ATE_DB_NAME and $ATE_INDEX are exported into the command:
# DB_CREATE_CMD='neon branches create --name $ATE_DB_NAME'
# DB_DROP_CMD='neon branches delete $ATE_DB_NAME'
#
# Or take full control by defining the hook functions (they override the keys
# above, exactly like ate_start_*). $ATE_DB_NAME is exported before they run:
# ate_db_create() { createdb "$ATE_DB_NAME" && psql "$ATE_DB_NAME" -f schema.sql; }
# ate_db_drop()   { dropdb --if-exists "$ATE_DB_NAME"; }

# Default stop behavior (no config needed): kill whatever is bound to this
# tree's ports. Set STOP_* nowhere; the built-in ate_stop_* hooks already do it.

# ---------------------------------------------------------------------------
# Escape hatch: define the hooks yourself.
#
# The declarative vars above are consumed by DEFAULT hook functions that
# ataegina defines before sourcing this file. If your stack needs something the
# declarative form cannot express (a process manager, docker compose, multiple
# processes, a custom readiness wait), define the hook function here and it
# OVERRIDES the default. You then own starting the server; reference whichever
# of the exported vars your framework expects.
# ---------------------------------------------------------------------------

# ate_start_backend() {
#   cd "$REPO_ROOT/backend" || return 1
#   PORT="$BACKEND_PORT" your-backend-start-command \
#     > "$DEV_LOG_DIR/backend.log" 2>&1 &
#   echo "backend  -> http://localhost:$BACKEND_PORT  (log: $DEV_LOG_DIR/backend.log)"
# }

# ate_start_frontend() {
#   cd "$REPO_ROOT/frontend" || return 1
#   PORT="$FRONTEND_PORT" \
#   PUBLIC_API_BASE_URL="$FRONTEND_API_BASE_URL" \
#     your-frontend-start-command \
#     > "$DEV_LOG_DIR/frontend.log" 2>&1 &
#   echo "frontend -> http://localhost:$FRONTEND_PORT  (log: $DEV_LOG_DIR/frontend.log)"
# }

# Stop hooks are optional. The defaults kill whatever is bound to this tree's
# ports, using the resolved port backend (lsof/ss/fuser) to find the pids;
# override them only if `ataegina down` should do something else. The helpers
# ate_port_pids / ate_port_listening are available to your override.
# ate_stop_backend() {
#   ate_port_pids "$BACKEND_PORT" | xargs kill 2>/dev/null || true
# }
# ate_stop_frontend() {
#   ate_port_pids "$FRONTEND_PORT" | xargs kill 2>/dev/null || true
# }

# ---------------------------------------------------------------------------
# Optional diagnostics hook. If you define ate_doctor, `ataegina doctor` calls
# it last, after its own read-only checks, so you can add stack-specific checks
# (CORS origins, sidecar reachability, database wiring). It is called with no
# arguments and inherits the same exported env the start hooks see. Keep it
# read-only and print your own [ok] / [warn] lines.
# ---------------------------------------------------------------------------
# ate_doctor() {
#   if curl -fsS "http://localhost:$BACKEND_PORT/health" >/dev/null 2>&1; then
#     echo "[ok]   backend health endpoint responding on :$BACKEND_PORT"
#   else
#     echo "[warn] backend health endpoint not responding on :$BACKEND_PORT"
#   fi
# }
