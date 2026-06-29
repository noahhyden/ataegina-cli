> Historical design note (not current documentation). Captures the thinking at one point in time. Line numbers and counts below reflect the script as it was then and have since drifted.

# Onboarding redesign

Setup is currently the weakest part of ataegina. Getting it running takes about
five steps and assumes you can write bash hooks and already know your stack's
port quirks. That is a tool only its author would tolerate. This doc captures
the friction, the proposed fixes, and the order to build them.

Goal: **zero to running in one install line plus one command**, for common
stacks, with no bash authoring.

## Friction audit (ordered by how much each step hurts)

1. **Writing hooks in bash, and learning the env contract.** The config makes
   you define `ate_start_frontend` / `ate_start_backend` shell functions and
   understand the exported env (`FRONTEND_PORT`, `BACKEND_URL`, `REPO_ROOT`,
   ...). Worse, you have to discover stack quirks yourself: Next pins
   `next dev -p 5173` in its `dev` script, so a naive `npm run dev` silently
   ignores the assigned slot and every tree fights over 5173. Nobody should have
   to learn that to use the tool.
2. **(Removed.)** An earlier cut shipped a stacked-PR retarget GitHub workflow.
   It was dropped as out of scope: it is not part of the core worktree tool, and
   pushing it tripped the `workflow` OAuth scope for no product gain. The other
   points here are all about the launcher itself.
3. **Getting the launcher on PATH.** Clone, then symlink (needs sudo) or add an
   alias. Multi-step and OS-dependent.
4. **Two-place config plus a resolution order** to learn (`$ATE_CONFIG` vs repo
   root vs `$XDG_CONFIG_HOME`).
5. **Silent stack gotchas.** CORS, shared sidecars, per-tree database isolation
   surface as "it just does not work" with no diagnostics pointing at the cause.

## Proposed work

### 1. `ataegina init` (auto-detect scaffolder) [P0, highest leverage]

Run it in a repo; it sniffs the stack and writes a working `ataegina.config.sh`,
then tells you what it detected so you can eyeball it. Removes friction 1, 4, and
most of 5 in one move.

- **Frontend detectors:** read `package.json` `scripts.dev`; classify Vite /
  Next / CRA / SvelteKit / Astro; **detect a hardcoded `-p`/`--port` and rewrite
  the start command to honor the assigned slot** (the exact Next trap above);
  pick the right API-base env var name (`NEXT_PUBLIC_*`, `VITE_*`, `PUBLIC_*`).
- **Backend detectors:** `pyproject.toml`+uv / poetry / `requirements.txt`
  (uvicorn/gunicorn), Django `manage.py`, Rails `Gemfile`, Express/Nest
  (`package.json`), Go `go.mod`. Emit a PORT-aware start command.
- **Output:** a prefilled config, with a comment block showing what was detected.
  `--dry-run` prints the config without writing.
- **Fallback:** undetected stack writes today's template with `TODO` hooks.

### 2. ~~Reusable workflow~~ (dropped)

The stacked-PR retarget workflow was removed from ataegina entirely. It is a
separate concern from the worktree harness, and it is what tripped the
`workflow` OAuth scope. If a PR-stacking helper is ever wanted, it belongs in its
own tool, not bolted onto this one.

### 3. One-line, sudo-free installer [P1]

`curl -fsSL <host>/install.sh | sh` drops the single launcher into `~/.local/bin`
(or the first writable dir on PATH), `chmod +x`, and prints an alias hint if that
dir is not on PATH. Removes friction 3. Follow-up: a Homebrew tap
(`brew install noahhyden/tap/ataegina`).

### 4. `ataegina doctor` [P2]

Diagnostics that turn silent failure into actionable output: check PATH, report
which config file won resolution, test port availability for this tree's slot,
confirm the hooks are defined, and print the per-tree URLs. Flag the common
traps explicitly ("your frontend dev script pins a port; init will override it",
"port 8003 already bound", "no config found, run `ataegina init`").

## Priority

- **P0:** `ataegina init` auto-detect. The difference between "write bash" and
  "run one command."
- **P1:** installer.
- **P2:** `doctor`.
- **P3:** Homebrew tap; zero-config (run detectors live when no config exists,
  so bare `ataegina up` works for common stacks).

## Open questions

- **Declarative config vs bash functions.** A `KEY=VALUE` layer (frontend dir +
  command, backend dir + command) would be friendlier for the 90% case; bash
  functions stay for power users. `init` could emit either. Decide before
  building `init` since it sets the format.
- **Zero-config `up`.** Should `ataegina up` with no config run detectors live,
  or require `init` first? Leaning: require `init` for explicitness, but suggest
  it in the no-config error.
- **Windows.** The launcher is bash; document WSL / Git Bash rather than port it.
- **Multi-service backends** (the shared-sidecar case): out of scope for v1;
  `doctor` warns rather than manages.

## Decisions (locked 2026-06-22)

- **B1 config format:** support both, declarative-first. `init` emits `KEY=VALUE`
  config; the launcher ships default hooks that consume it; a user-defined
  `ate_start_*` function in the config overrides (power-user escape hatch).
- **B2 v1 stack coverage:** frontend Next / Vite / CRA; backend uv-FastAPI /
  Django / Express. Anything else falls back to a commented TODO template.
- **B3 interaction model:** **interactive by default** (the audience skews
  beginner and will want the prompts); `--yes` / `--non-interactive` opts out for
  scripting and CI. (This reverses the earlier pure-detect lean.)
- **B4-B6 (stacked-PR workflow):** dropped. The workflow was removed from
  ataegina as out of scope, so these decisions no longer apply.
- **B7 installer host:** raw GitHub pinned to a tag for v1; a pretty install
  alias domain later.
- **B8 install priority:** `curl | sh` first, Homebrew tap immediately after.
- **B9 repo visibility:** stays **private** for now. Consequence: the raw-GitHub
  installer (#3) is build-but-dormant until a future go-public; it works via
  authenticated clone in the meantime.
- **B10 versioning + extension:** adopt semver tags (`v1` moving + `vX.Y.Z`
  immutable); `doctor` runs an optional user-defined `ate_doctor` hook so
  stack-specific checks (CORS, sidecars) live in the user's own config.

Resolved open questions: declarative-vs-bash is settled (both). Zero-config `up`
stays P3. Windows stays "use WSL / Git Bash." Multi-service backends are handled
by the `ate_doctor` extension hook rather than by the tool directly.
