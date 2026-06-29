> Historical design note (not current documentation). Captures the thinking at one point in time. Line numbers and counts below reflect the script as it was then and have since drifted.

# Spike: smart per-worktree ports (start only the surfaces a task needs)

Status: investigation + working PoC. Nothing here modifies the committed
`ataegina` script. All code lives in this scratchpad.

## The problem

On a low-tier machine, `ataegina up` (today) starts BOTH the frontend (`5173+N`)
and the backend (`8000+N`) in every worktree. Most tasks touch one surface, or
neither. We want a worktree to start only what its task actually needs, and for
any surface it does not need, point at the SHARED DEFAULT already running in the
primary checkout (frontend `5173`, backend `8000`).

Target behavior:

| task touches | start locally | point at shared default |
|---|---|---|
| frontend only | frontend `5173+N` | backend -> `localhost:8000` |
| backend only  | backend `8000+N`  | (no local frontend; see sharing-direction) |
| neither       | nothing | use `5173` / `8000` directly |
| both          | both (today's behavior) | nothing |

---

## 1. Recommendation

**Primary mechanism: sampled git-diff classification at `up` time (and on an
explicit `refresh`), with a task-spec `scope:` field and a `--scope` flag as
overrides. This is the hybrid (approach 5), defaulting to approach 2.**

Resolution order, first hit wins:

1. `--scope frontend|backend|both|none` on the command line (one invocation).
2. `scope:` in the task spec front-matter (authoritative when the agent/author
   declared intent).
3. Sampled git-diff classification (`ate_task_scope`) -- the zero-touch default.
4. Fallback: `both` (today's behavior) if not in a git context or anything is
   ambiguous.

Why sampled git-diff as the default and not "explicit only": the dispatcher
already creates one worktree per task from a known base branch, so a clean
diff signal is sitting right there for free. Asking every task author/agent to
declare scope correctly is a footgun (they will forget, or guess wrong, and
then a backend change silently runs against a stale shared backend). The diff
is the ground truth of what changed; the declaration is a hint. Use the hint
to *override*, not as the only source.

Why keep the override: the diff is blind to intent at the very start of a task
(empty diff = `none`, so nothing starts) and to "I am about to touch the
backend but have not yet." The `scope:` field lets an agent say "this is a
backend task" up front so the right server is hot before the first edit.

---

## 2. PoC: `ate_task_scope`

Working, tested bash. Prints `frontend` / `backend` / `both` / `none`. Pure
git plumbing + prefix matching, zero non-git dependencies. Lives at
`scope-poc.sh` in this scratchpad.

```bash
# ate_task_scope WORKTREE BASE_REF FRONTEND_DIR BACKEND_DIR -> frontend|backend|both|none
ate_task_scope() {
  local wt="$1" base="$2" fe_dir="$3" be_dir="$4"
  # Normalize dir prefixes: strip slashes, force ONE trailing slash so that
  # 'app/' never prefix-matches 'apps/web/'. Empty dir => sentinel (matches nothing).
  local fe be
  fe="${fe_dir#/}"; fe="${fe%/}"
  be="${be_dir#/}"; be="${be%/}"
  [ -n "$fe" ] && fe="$fe/" || fe=$'\x01'
  [ -n "$be" ] && be="$be/" || be=$'\x01'

  # Diff base: merge-base with the base ref, so we only see what THIS branch
  # added, not what base accumulated after the fork. Fall back to the raw ref.
  local mb=""
  if [ -n "$base" ]; then
    mb="$(git -C "$wt" merge-base "$base" HEAD 2>/dev/null || true)"
    [ -z "$mb" ] && git -C "$wt" rev-parse --verify -q "$base" >/dev/null 2>&1 && mb="$base"
  fi

  # Three cheap samples: committed-since-base, tracked working changes (staged
  # + unstaged via `diff HEAD`), and untracked files (which `diff HEAD` misses).
  local paths
  paths="$(
    { [ -n "$mb" ] && git -C "$wt" diff --name-only "$mb"..HEAD 2>/dev/null
      git -C "$wt" diff --name-only HEAD 2>/dev/null
      git -C "$wt" ls-files --others --exclude-standard 2>/dev/null
    } | sort -u
  )"
  [ -z "$paths" ] && { echo none; return 0; }

  local saw_fe=0 saw_be=0 saw_other=0 p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p/" in
      "$fe"*) saw_fe=1 ;;
      "$be"*) saw_be=1 ;;
      *)      saw_other=1 ;;
    esac
  done <<EOF
$paths
EOF

  # Conservative: anything outside both dirs (shared libs, schema, root config)
  # forces 'both'. FE+BE both touched also 'both'.
  if [ "$saw_other" = 1 ]; then echo both; return 0; fi
  if [ "$saw_fe" = 1 ] && [ "$saw_be" = 1 ]; then echo both; return 0; fi
  if [ "$saw_fe" = 1 ]; then echo frontend; return 0; fi
  if [ "$saw_be" = 1 ]; then echo backend; return 0; fi
  echo none
}
```

### Test results (throwaway repo, staged / committed / untracked under each dir)

```
clean tree                                              expected=none      got=none      OK
untracked FE only                                       expected=frontend  got=frontend  OK
untracked BE only                                       expected=backend   got=backend   OK
unstaged FE edit                                        expected=frontend  got=frontend  OK
staged BE edit                                          expected=backend   got=backend   OK
committed FE only                                       expected=frontend  got=frontend  OK
committed FE + BE                                       expected=both      got=both      OK
shared lib (OTHER) only                                 expected=both      got=both      OK
root file (OTHER, uncommitted)                          expected=both      got=both      OK
committed FE + untracked OTHER                          expected=both      got=both      OK
edit apps/web   dirs=apps/web,apps/api  -> frontend  OK   (nested prefixes)
edit apps/web   dirs=app,api            -> both      OK   (prefix-collision guard)
edit app/       dirs=app,api            -> frontend  OK
merge-base isolates main BE commit      -> frontend  OK   (base divergence)
```

All 14 cases pass. The two important correctness guards:

- **Prefix-collision guard.** With `FRONTEND_DIR=app`, a change under `apps/web/`
  does NOT count as frontend (it falls to OTHER -> `both`). The single-trailing-
  slash normalization (`app/` vs `apps/web/`) is what buys this.
- **Base-divergence isolation.** A backend commit that lands on `main` *after*
  the branch forked does not leak into the branch's scope, because we diff from
  `merge-base(base, HEAD)`, not from `base` directly.

### Cost

~37 ms per call (three git plumbing invocations) in a small repo; a few git
process spawns even in a large repo. Run once per `up` and once per `refresh`.
Negligible. This is the whole point of "sampled, not real-time": you pay it
twice in a task's life, not on every file save.

---

## 3. UX / wiring design

### How `ataegina up` consumes the scope

`up` gains an optional auto-detect path. Today `MODE` is `both|backend|frontend`
taken from `$2`. Add a fourth literal `auto` (and make it the default when the
config opts in), plus `none`:

```
ataegina up            # MODE=auto if scope-aware, else both (unchanged for opt-out)
ataegina up auto       # detect scope, start only what is needed, share the rest
ataegina up frontend   # explicit, unchanged
ataegina up --scope backend   # explicit override of detection
```

`auto` resolves the scope (override chain from section 1), then:

```
scope=frontend -> start frontend locally; export BACKEND_URL pointing at the
                  shared default backend (see liveness check below); do NOT
                  start a local backend.
scope=backend  -> start backend locally; do NOT start a local frontend (the
                  agent/tests hit the backend directly). If a frontend is
                  genuinely wanted, the shared default frontend on :5173 is
                  repointed -- see sharing-direction caveat.
scope=both     -> today's behavior: both local.
scope=none     -> start nothing; print the shared default URLs and exit 0.
```

### Env-var changes (concrete)

Today `up` unconditionally exports, for index N:

```
BACKEND_URL=http://localhost:$((BACK_PORT_BASE+N))
FRONTEND_API_BASE_URL=http://localhost:$((BACK_PORT_BASE+N))
```

Under `auto`, the exported `BACKEND_URL` / `FRONTEND_API_BASE_URL` are computed
from the scope, NOT blindly from N:

```
# pseudo, inserted after N/ports are resolved, before the hooks run
SHARED_BE="http://localhost:$BACK_PORT_BASE"     # the primary's backend (:8000)
SHARED_FE="http://localhost:$FRONT_PORT_BASE"    # the primary's frontend (:5173)
LOCAL_BE="http://localhost:$BE_PORT"             # this tree's backend (8000+N)

case "$SCOPE" in
  frontend)
    # frontend runs here, talks to the shared backend
    ensure_shared_listening "$BACK_PORT_BASE" backend  # liveness + fallback
    export BACKEND_URL="$SHARED_BE"
    export FRONTEND_API_BASE_URL="$SHARED_BE"
    ate_start_frontend
    ;;
  backend)
    # backend runs here; nothing else started. The frontend env is irrelevant
    # because no local frontend is launched. (BACKEND_URL stays = LOCAL_BE so
    # any health-check / curl the agent runs hits this tree's backend.)
    export BACKEND_URL="$LOCAL_BE"
    ate_start_backend
    ;;
  both)  # unchanged: both local, BACKEND_URL = LOCAL_BE
    export BACKEND_URL="$LOCAL_BE"; export FRONTEND_API_BASE_URL="$LOCAL_BE"
    ate_start_backend; ate_start_frontend
    ;;
  none)
    log "scope=none -> nothing to start. shared: $SHARED_FE  $SHARED_BE"
    ;;
esac
```

The key wiring fact ataegina already gives you: the frontend's API base URL is
already a single exported var (`FRONTEND_API_BASE_URL`, and the per-framework
`FRONTEND_ENV` like `NEXT_PUBLIC_API_BASE_URL=$BACKEND_URL`). So "point the
frontend at the shared backend" is literally "set `BACKEND_URL` to `:8000`
before calling `ate_start_frontend`." No hook changes needed; the declarative
config already threads `$BACKEND_URL` into the frontend command's env.

### Liveness check + fallback (the shared default must actually be up)

Pointing at `localhost:8000` is only safe if the primary's backend is listening.
Reuse the existing `lsof`-based idiom from the start hooks:

```bash
# True if something is listening on a TCP port (same probe the hooks use).
ate_port_listening() { lsof -ti tcp:"$1" >/dev/null 2>&1; }

# Ensure the shared default for SIDE is up; if not, fall back to starting a
# LOCAL one on this tree's slot and rewire to point at it.
ensure_shared_listening() {
  local port="$1" side="$2"
  if ate_port_listening "$port"; then
    log "scope: reusing shared $side on :$port"
    return 0
  fi
  log "scope: shared $side on :$port is DOWN -> starting a local $side instead"
  case "$side" in
    backend)
      ate_start_backend            # starts on BE_PORT (8000+N)
      export BACKEND_URL="$LOCAL_BE"
      export FRONTEND_API_BASE_URL="$LOCAL_BE"
      ;;
    frontend) ate_start_frontend ;;
  esac
}
```

So a frontend-only task whose shared backend is down degrades gracefully to
today's both-local behavior for that side, instead of breaking. This is the
safety net that makes "share the default" acceptable: worst case you start what
you would have started anyway.

### The `--scope` flag and the `scope:` task field

`--scope X` is parsed in the `up` arg loop and short-circuits detection.

The task-spec field rides on the existing markdown task files (one `*.md` per
task, id = filename). A YAML-ish front-matter block, parsed with the same
grep/sed style already used in the script (`pkg_dev_script` shows the pattern --
no YAML parser):

```markdown
---
scope: backend
---
# Task: tighten the rate-limiter

...task body...
```

```bash
# Read scope: from a task md front-matter. Empty if absent. No YAML dep.
ate_task_scope_field() {
  local f="$1"
  [ -f "$f" ] || return 0
  grep -oiE '^scope:[[:space:]]*(frontend|backend|both|none)' "$f" 2>/dev/null \
    | head -n1 | sed -E 's/^scope:[[:space:]]*//I'
}
```

The dispatcher (`dispatch_launch`) already exports `ATE_TASK_FILE` per task and
runs the agent in the worktree. It can read `scope:` there and export
`ATE_SCOPE`, which a worktree's `ataegina up auto` then honors as the
declared-override tier. So the fleet wiring is: dispatcher reads the field once,
the per-worktree `up` reads the diff, declaration wins if present.

---

## 4. Feasibility verdict for a low-tier machine

**Worth it, with a caveat about where the real saving is.**

The real cost on a low-tier box is the *running* dev servers (a Next dev server
+ a Python/uvicorn reloader is hundreds of MB of RAM and constant CPU from file
watchers), not the launch. So the saving is real and proportional to how many
worktrees are open at once:

- A `frontend`-only task drops a whole backend process (and its DB connections /
  file watcher). On a 4-worktree fleet where 3 are frontend-only, that is 3
  backends not running -- a large RAM/CPU win.
- A `none` task (docs, config-only chore) starts nothing at all. Pure win.
- `both` is unchanged, so the worst case is no worse than today.

Cost added is small and contained:

- One ~37 ms classification per `up`/`refresh`. Trivial.
- ~60 lines of bash (the function + the `auto` branch + liveness/fallback +
  field/flag parsing). All in the existing idioms (lsof, awk/grep/sed, git
  plumbing). Zero new dependencies.

Where it breaks / sharp edges:

1. **Shared-state coupling.** Frontend-only tasks now depend on the primary
   checkout's backend being up AND on a compatible API contract. If your branch
   changed the API shape but classified as `frontend` (because the contract
   change was a generated type under `frontend/`), the shared `:8000` backend
   will not speak the new contract. The conservative OTHER->`both` rule mitigates
   the common version of this (schema/shared-lib edits force `both`), but a
   frontend-resident type change can still slip through. Acceptable: that is a
   genuinely frontend-only change by directory, and the override field exists for
   the author who knows better.
2. **Backend-only + a frontend.** If an agent's verification actually needs a
   browser hitting a UI, `backend`-only starts no frontend. See sharing-direction
   below -- this is the asymmetric case and the honest answer is "usually fine,
   occasionally needs `both`."
3. **Empty-diff cold start.** A brand-new task has an empty diff -> `none` ->
   nothing starts. Without the `scope:` field, the first server only comes up on
   the first `refresh` after the first edit. The field is the fix; document that
   declaring `scope:` is the way to pre-warm.
4. **Primary checkout is itself a worktree running `auto`.** The shared default
   only exists if *something* is serving `:5173`/`:8000`. Keep the convention
   that the primary checkout (index 0) runs `both` (or is the dedicated shared
   stack). If index 0 also goes `auto`, "shared default" can evaporate -- the
   liveness fallback covers correctness but you lose the saving.

### Sharing direction (the hard part), worked out

- **Frontend sharing a backend: clean and the main win.** A frontend is a pure
  client of the backend over HTTP. Point its API base URL at `:8000` and it
  works, because nothing about the running frontend constrains the backend. One
  shared backend can serve N frontends. This is the case the design optimizes.

- **Backend sharing a frontend: mostly does NOT apply.** A backend-only task's
  changed backend is exercised by the agent/tests hitting it directly (curl,
  pytest, the agent's own HTTP calls) -- it does not *need* a frontend at all.
  So the right default for `scope=backend` is **start backend only, start no
  frontend.** The naive idea "repoint the shared `:5173` frontend at this tree's
  `:8000` backend" is wrong in a fleet: the shared frontend has exactly one API
  base URL, so you cannot repoint it for one worktree without breaking it for
  the primary and every other frontend-only worktree. Frontend->backend fan-out
  works (many clients, one server); backend->frontend fan-in does not (one
  frontend can target only one backend). Hence the table's "no local frontend"
  for backend-only, and the escape is `--scope both` when a UI really is needed.

  Direction summary: **a server can be shared by many clients; a client cannot be
  shared across many servers.** Backend = server, frontend = client. So backends
  are shareable downward (frontends point at them), frontends are not.

### Classification rule for changes outside both dirs

Conservative by construction: any changed path that is not under `FRONTEND_DIR`
nor `BACKEND_DIR` (shared libs, generated types at the root, DB schema/migrations,
root config like `package.json`, lockfiles, CI, env templates) sets `saw_other`
and forces **`both`**. Rationale: such a change can affect either surface, and
guessing wrong here is the expensive failure (a silently-stale shared backend),
so we pay for a local backend rather than risk it. This is the single rule that
makes the whole scheme safe to default-on.

### Base for the diff

`merge-base(BASE, HEAD)` where BASE is the dispatcher's base branch
(`DISPATCH_BASE` / `ATE_BASE_BRANCH`, default the repo's current branch at run
start). Using the merge-base, not BASE directly, means commits that land on the
trunk after the branch forked do not pollute the branch's scope (verified in the
tests). For a hand-run `ataegina up` outside the dispatcher, default BASE to the
upstream/trunk if set, else fall back to diffing the working tree against HEAD
only (still catches all uncommitted + staged + untracked work).

### Stale decisions when scope grows mid-flight

A task that starts docs-only (`none`) and grows into a backend change needs its
backend started late. Cheap re-evaluation handles it without real-time tracking:

- **On `up` and on an explicit `ataegina refresh`** (new tiny subcommand: re-run
  detection, start newly-needed surfaces, leave running ones alone -- the start
  hooks are already idempotent via the `lsof` guard, so re-running `up auto` is
  safe and only starts what is missing).
- **Optional `post-commit` hook** in the worktree that runs `ataegina refresh`,
  so a commit that first touches the backend auto-starts it. One line, opt-in.
- **Dispatcher tick.** `dispatch_tick` already runs every 2s per task. It can
  re-classify on a low duty cycle (for example every Nth tick) and start a newly
  needed surface. Re-classification is ~37 ms and the start hooks are idempotent,
  so this is cheap. This is the "approach 3" re-evaluate-periodically option, and
  it composes for free with the existing supervisor loop -- no new daemon.

The point: scope only ever *grows* (frontend -> both, none -> something), and
adding a server is idempotent and cheap, so periodic re-sampling fully covers
staleness. You never need to tear a server down on shrink.

---

## 5. Is the "real-time is a pain" instinct right?

**Confirmed.** Real-time git-diff tracking (a file watcher / inotify / fswatch
loop re-running classification on every save) is the wrong tool here:

- It needs a long-lived watcher process per worktree (a daemon to supervise,
  another thing to leak and to kill on `down`), which is exactly the kind of
  weight a low-tier-machine optimization is trying to avoid.
- `fswatch`/`inotifywait` are non-portable extra dependencies; ataegina is
  deliberately zero-dep pure bash. A real-time scheme breaks that constraint.
- It buys almost nothing over sampling. Scope only changes at commit/edit
  boundaries, and the only actionable transition is "a new surface became
  needed," which is idempotent to act on late. Sampling at `up` + on commit +
  on the dispatcher tick catches every such transition within seconds, at the
  cost of three git commands.

So the lighter path is exactly the one in the prompt's approach 2: **sample the
diff at `up` and on `refresh` (plus the free dispatcher-tick re-sample), not in
real time.** Approach 4 (a lazy port-knock proxy that boots a server on first
hit) is heavier still -- it needs a resident listener/proxy on every shared
port, has to detect "first hit," and adds a cold-start latency spike on the
first request; the complexity dwarfs the payoff for a dev harness. Recommend
against it.

---

## Appendix: files in this scratchpad

- `scope-poc.sh` -- the tested `ate_task_scope` function.
- `spike-smart-ports.md` -- this document.
- `scope-test-repo/`, `scope-test-repo2/` -- throwaway test repos.
