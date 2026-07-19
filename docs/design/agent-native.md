# Agent-native CLI surface

Ataegina's stated audience is coding agents running fleets of parallel
worktrees. Agents consume a CLI differently from humans: they parse output
programmatically, they must query state before acting to stay idempotent, and
they need to know when a server is *actually reachable*, not merely spawned.
This doc specs five additions that make the surface agent-native without
changing the tool's identity (one bash file, no daemon, no deps).

The features share one contract — a stable JSON object for a worktree's derived
slot — so `ports`, `status`, `up`, and `list` all speak the same shape.

## The shared slot object

Every command that describes a worktree's slot emits (as a field or a whole
document) this object:

```json
{
  "index": 1,
  "repo_root": "/abs/path/to/worktree",
  "frontend": { "port": 5174, "url": "http://localhost:5174" },
  "backend":  { "port": 8001, "url": "http://localhost:8001" },
  "log_dir": "/tmp/ate-wt1",
  "db": { "name": "myapp_wt1", "url": "postgres://localhost:5432/myapp_wt1" }
}
```

`db` is `null` when no database is configured (`DB_NAME` unset). `db.url` is
`null` when `DB_NAME` is set but `DB_URL_TEMPLATE` is not. All strings are
JSON-escaped (`"`, `\`, and control chars). Emission is bash-3.2-safe and uses
no external JSON tool (consistent with the rest of the script).

## 1. `ports --json`

`ataegina ports` gains a `--json` flag. Without it, unchanged human output. With
it, prints exactly the shared slot object (single line or pretty — single line,
so it is greppable and pipe-friendly) and nothing else on stdout. Read-only.

## 2. `up --wait[=SECONDS]`

`up` already *reports* readiness (polls ~8s, then says "still starting"). `--wait`
turns that into a *contract*: block until every server this invocation launched
is accepting TCP connections, up to SECONDS (default 60), and **exit nonzero
(75)** if any is not ready by the deadline. This lets an agent do
`ataegina up --wait && curl "$BACKEND_URL/health"` without a hand-rolled poll
loop and without racing a not-yet-bound port. `--wait` with no value uses the
default; `--wait=N` or `ATE_UP_WAIT=N` sets the timeout. Exit 0 when everything
launched is ready (or when nothing was launched, e.g. scope none).

## 3. `status [--json]`

A new read-only command: "is this tree up, and where?" — the side-effect-free
query agents need before acting. Human form prints a compact per-surface state;
`--json` prints the slot object with `state` + `pid` folded into the
frontend/backend sub-objects:

```json
{ "index": 1, "repo_root": "...",
  "frontend": { "port": 5174, "url": "...", "state": "running", "pid": 1234 },
  "backend":  { "port": 8001, "url": "...", "state": "stopped", "pid": null },
  "log_dir": "...",
  "db": { "name": "myapp_wt1", "url": "..." } }
```

`state` is one of `running` (a live server we launched holds the port),
`foreign` (something we did not launch holds it), `unknown` (the port is held
but ownership can't be verified — often our own reparented daemon), or `stopped`
(nothing on the port). `pid` is the holder's pid (integer) or `null` when
nothing holds the port or the port backend can't map pids. `db` is the same
non-probed object as the slot shape (status never connects to the database).
Reuses `_ate_port_ownership` + `ate_port_pids`. Never mutates; exit 0 regardless
of state (state is data, not failure).

## 4. `up --json`

`up` gains `--json`: after starting the resolved scope, print one slot object
augmented with what this invocation did — a `started` array (`["backend",
"frontend"]`) and, per surface it launched, a `ready` boolean (honoring
`--wait`'s polling). Closes the "run up, then separately run ports to learn the
slot" round-trip. Human output is suppressed to stderr under `--json` so stdout
is pure JSON.

## 5. `list --json`

`ataegina list` gains `--json`: an array of every registered worktree (including
the primary at index 0), each entry the slot object plus `"stale": bool` (its
directory is gone) and, when port tooling can see it, a coarse `"live": bool`
(any of its derived ports is listening). This is the fleet view a supervising
agent uses to see all its workers at once. Human output unchanged without the
flag.

## Non-goals

No MCP server (a daemon + runtime would contradict the single-file, no-daemon
identity; a shell-native agent gets more from `--json` + `exec`/`env`, which
already exist). No pretty-printing/coloring of JSON. No new dependencies.
