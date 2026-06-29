> Historical design note (not current documentation). Captures the thinking at one point in time. Line numbers and counts below (e.g. the script size) reflect the script as it was then and have since drifted.

# Spike: ataegina portability, install, config, licensing, updates

Status: investigation + recommendation. No code shipped. Grounded in a full
read of the `ataegina` script (1342 lines), the README, the example config, and
the docs.

## Executive summary

ataegina is in unusually good shape for cross-platform use. It is strict-mode
bash (`set -euo pipefail`) with a portable shebang (`#!/usr/bin/env bash`), and
it deliberately avoids every bash-4-only construct: no associative arrays, no
`declare -A`, no `mapfile`/`readarray`, no `${var^^}`, no `&>>`, no process
substitution, no here-strings. It already runs on the macOS system bash 3.2 as
written. The one genuine GNU-vs-BSD divergence in the codebase, `stat`, is
already handled portably (line 721 tries `stat -f` then `stat -c`).

The real portability story is therefore not the bash dialect, it is the external
tools the script shells out to:

- **`lsof`** is the load-bearing dependency for every port operation (start
  guard, stop, doctor, scope sharing). It is preinstalled on macOS but **not** on
  a minimal Debian/Ubuntu. This is the single most likely "fresh Linux box"
  failure.
- **`git`** is required everywhere (worktree-aware by design).
- **`gh`** is optional and already gated cleanly (PR step skips if absent).
- **`nohup`/`disown`** detach the dev servers and agents; these work on macOS and
  Linux and in WSL2, but `disown` behaves differently under Git Bash / MSYS2.

Verdicts at a glance:

- **Platform matrix:** Linux full (after `apt install lsof`), macOS full as-is,
  Windows full via WSL2, partial via Git Bash, no via native PowerShell/cmd.
- **Min install steps:** realistically **one** command (`curl | sh` into
  `~/.local/bin`), fully sudo-free.
- **sudo:** not required, and not worth requiring. Nothing this tool does needs
  it.
- **Config:** `init` already writes the file and is interactive; lean into that
  plus a small `ataegina config get/set` so the file is rarely hand-edited. Keep
  the sourced-bash format. Do not adopt TOML/INI.
- **Updates:** a manual `ataegina update` self-replace plus an opt-in,
  off-by-default, once-a-day, offline-safe "newer version available" check.
  Never silent auto-update.

---

## 1. Cross-platform support matrix

### Portability hazards found in the script (with line refs)

What I looked for and what is actually there:

- **bash 4+ constructs: NONE.** No `declare -A`, `mapfile`/`readarray`,
  `${var^^}`/`${var,,}`, `&>>`, `|&`, process substitution `<(...)`, or
  here-strings `<<<`. The script uses POSIX-style heredocs instead (e.g. the
  `while read ... <<EOF / $rows / EOF` pattern at lines 227-229 and 964-966),
  which is the bash-3.2-safe way to feed a variable into a loop. Confirmed by
  running the script's own constructs under `/bin/bash 3.2.57` (the macOS system
  bash) without error.
- **`stat` (GNU vs BSD): already portable.** Line 721:
  `stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0`. BSD
  form first, GNU fallback, then `0`. Correct.
- **No `sed -i`, no `readlink -f`, no `date -d`, no `date -r`, no `grep -P`.**
  These are the usual GNU-only traps and none appear. `date` is only ever
  `date +%s` (line 816, 888), which is identical on both platforms.
- **`sed -E` and `tr 'A-Z' 'a-z'` (line 257): portable.** `-E` is supported on
  both GNU and modern BSD sed; `tr` with explicit ranges avoids locale issues.
- **`xargs -r` (lines 169-170): now portable, was a classic BSD trap.** `-r`
  (`--no-run-if-empty`) was historically GNU-only, but current macOS BSD `xargs`
  supports it (verified in this environment's man page and by running it). On a
  very old BSD it would error, but the pipe feeding it (`lsof -ti ... | xargs`)
  only matters when there is a PID to kill, so the empty case is also the only
  divergent case. Low risk; worth a one-line portability note, not a fix.
- **`read -r -p ... </dev/tty` (line 312): fine, and guarded.** Reading the
  prompt from `/dev/tty` is correct (lets `init` prompt even when stdin is a
  pipe), and it has an `|| { echo "$default"; return; }` fallback for when no tty
  exists. `/dev/tty` does not exist on native Windows, but that path is only hit
  under a real terminal and `init` already drops to non-interactive on a non-tty
  (line 493).
- **`mktemp`, `ps -o comm=`, `lsof -ti tcp:`: BSD/GNU-compatible spellings.**
  `ps -p PID -o comm=` (line 676) and `lsof -ti tcp:PORT` work the same on macOS
  and Linux.

Net: the script is already written to a high portability bar. The hazards are
environmental (is `lsof` installed, is this a real POSIX shell) not lexical.

### macOS

**Runs today: YES, as-is, on the system `/bin/bash` 3.2.** No bash 4 features are
used, so a brew bash is not required. The `#!/usr/bin/env bash` shebang will pick
up a newer brew bash if one is first on PATH, which is harmless. BSD tool usage
is either already dual-pathed (`stat`) or compatible (`sed -E`, `xargs -r`,
`ps`, `lsof`, `date +%s`). `lsof` and `git` ship with the OS / Xcode CLT.

What could break: nothing in the core. Edge case only: a user on a very old macOS
with an ancient BSD `xargs` predating `-r`, which is not a realistic target.

To make it work: nothing. It is the reference platform.

### Linux (Debian/Ubuntu)

**Runs today: YES on a developer box, with one caveat on a minimal box.** This is
the native bash + GNU coreutils environment, so the shell and `awk`/`sed`/`grep`/
`stat`/`date` all work. The caveat is package presence on a slim image:

- **`lsof` is frequently NOT installed** on minimal Debian/Ubuntu (and many
  containers). Every port check goes through `lsof` (lines 146, 159, 169-170,
  261, 672), so without it: `up` cannot detect "already up", `down` cannot
  kill-by-port, `doctor` cannot report port state, and scope-sharing cannot tell
  whether the shared backend is live. `git`, `awk`, `coreutils` are essentially
  always present; `gh` is not (already optional and gated, line 839).

Fallbacks to propose (any one unblocks the port checks without `lsof`):

- `ss -ltnp` (iproute2, present on virtually all modern Linux) to list listeners
  by port for the "is it up" probe.
- `fuser -k <port>/tcp` for kill-by-port in the stop hooks.
- `/proc/net/tcp` parse (zero extra packages) as a last-resort listener check.

Honest alternative: keep `lsof` as the single probe and just document
`sudo apt-get install lsof git` (and optionally `gh`) in the README requirements.
A small internal `ate_port_pids()` shim that tries `lsof`, then `ss`, then
`fuser` would make a fresh minimal box work with zero user setup; that is the
higher-quality option (see change list).

To make it work: `apt install lsof` today, or add the `ss`/`fuser` fallback shim.

### Windows 10/11

The honest three-way answer:

- **WSL2: full support, and this is the recommended Windows story.** Inside a
  WSL2 Ubuntu it is just Linux: native bash, `git`, `nohup`/`disown`, pid
  liveness via `kill -0`, `git worktree`, POSIX paths. The only setup is the same
  `apt install lsof` caveat as native Linux. The systemd user-service example
  (`examples/ataegina-run.service`) even works under WSL2 with systemd enabled.
- **Git Bash / MSYS2: partial.** The launcher's pure-bash core (`ports`, `list`,
  `prune`, registry math, `init` detection) works because it is all shell plus
  `git`. What breaks or gets shaky:
  - **`lsof`** is not part of Git Bash / MSYS2 by default, so port start-guard,
    stop, and doctor port checks fail the same way as minimal Linux.
  - **`nohup` + `disown`** are the riskiest. MSYS2 has `nohup`, but detaching a
    process so it outlives the shell is unreliable under the MSYS layer; agent
    and dev-server processes can be reaped when the parent shell exits, which
    defeats the dispatcher's whole "outlive the supervisor" model.
  - **pid liveness (`kill -0`)** works against MSYS pids but can mismatch native
    Windows pids if a command launches a Windows-native child, so the
    dispatcher's "is the agent still alive" check can be wrong.
  - **`git worktree`** works (it is plain git).
  - **paths** mostly work but the `/tmp/ate-wt*` log dirs and any absolute-path
    assumptions map through the MSYS pseudo-filesystem; mixing MSYS paths with a
    Windows-native agent CLI (e.g. a `.exe` that wants `C:\...`) is a known
    friction point.
  Verdict: usable for the launcher's bookkeeping and `init`, not trustworthy for
  the dispatcher's long-lived detached agents. Tell Git Bash users to prefer
  WSL2.
- **Native PowerShell / cmd: NO.** It is a bash script end to end. Running it
  natively would require a full PowerShell port (different process model,
  different port APIs, no `git worktree` semantics change but everything around
  it changes). Out of scope; not worth it.

Recommendation for Windows: **document WSL2 as the supported path**, note Git
Bash works for the launcher but not the dispatcher, and explicitly say native
PowerShell/cmd is unsupported. No code needed to make WSL2 work.

### The matrix (feature x platform)

Feature columns map to the four subsystems: **launcher** (`up`/`down`/`ports`/
`list`/`prune`), **init** (scaffolder), **doctor** (read-only), **dispatcher**
(`run`/`status`).

| Platform | launcher | init | doctor | dispatcher |
|---|---|---|---|---|
| macOS (system bash 3.2) | full | full | full | full |
| Linux dev box (lsof present) | full | full | full | full |
| Linux minimal (no lsof) | partial (port ops fail) | full | partial (port checks blank) | partial (PR gated anyway; port-based scope sharing degraded) |
| Windows WSL2 | full | full | full | full |
| Windows Git Bash / MSYS2 | partial (no lsof; detach shaky) | full | partial | no (detach/pid liveness unreliable) |
| Windows native PowerShell/cmd | no | no | no | no |

"partial" on minimal Linux collapses to "full" the moment `lsof` is installed (or
the `ss`/`fuser` fallback lands).

---

## 2. Installation: steps and sudo

### Install paths, counting literal steps

The README today shows `chmod +x` + `sudo ln -s ... /usr/local/bin` (Quickstart,
lines 33-35). That is the friction we want to remove. The single-file,
zero-dependency nature of the tool makes a one-command install trivial.

**(a) One-line `curl | sh` into `~/.local/bin` (recommended).**
```
curl -fsSL https://<host>/install.sh | sh
```
**1 step.** The installer script downloads the single `ataegina` file to
`~/.local/bin/ataegina`, `chmod +x`, and prints a PATH hint if `~/.local/bin`
is not already on PATH. No sudo. This is the realistic minimum and hits the
one-command target.

**(b) Homebrew tap.**
```
brew install <user>/tap/ataegina
```
**1 command, but 2 real steps** the first time (`brew tap <user>/tap` then
`brew install ataegina`, or the combined form above). Best for macOS users who
want `brew upgrade` to manage updates. Requires maintaining a tap formula. No
sudo (Homebrew installs into its own prefix).

**(c) Manual single-file download + chmod + PATH.**
```
curl -fsSLO https://<host>/ataegina      # 1
chmod +x ataegina                        # 2
mv ataegina ~/.local/bin/                # 3   (or add its dir to PATH)
```
**3 steps.** This is the "I want to read it first" path and the trust-conscious
default (see section 4). No sudo.

**Fewest steps:** (a) at one command. **Realistic minimum:** one command,
achievable today with a ~15-line POSIX `install.sh`.

### Is sudo required?

**No. A fully sudo-free install is achievable and should be the default.**
Installing to `~/.local/bin` (or `$HOME/bin`, or even a shell alias to the
checkout) needs no elevation. The script writes only under `$HOME`: the registry
defaults to `$XDG_CONFIG_HOME/.config/ataegina` (line 119), logs to `/tmp`
(world-writable, no sudo), worktrees to a sibling of the repo, dispatch state
under the registry dir. Nothing touches a root-owned path.

**The one caveat is PATH.** `~/.local/bin` is on PATH by default on most modern
distros and macOS shells, but not universally. The installer must detect this and
print the exact line to add (`export PATH="$HOME/.local/bin:$PATH"` in
`~/.zshrc`/`~/.bashrc`). `doctor` already checks "launcher on PATH" (lines
544-549), so a misconfigured PATH is self-diagnosing.

### Would requiring sudo unblock anything worth the friction?

Walking the candidates honestly:

- **System-wide install for all users** (`/usr/local/bin`): a convenience, not a
  capability. A per-user install gives every user the tool already, and a dev
  tool that mutates per-user git worktrees has no reason to be system-shared.
  Not worth it.
- **System-level (not user-level) systemd service:** the shipped example is a
  `--user` unit (`examples/ataegina-run.service`, `systemctl --user`,
  `loginctl enable-linger`), which needs no root. A system unit would let the
  dispatcher run without the user logged in, but it would then run agents as a
  system user against a user's repo and git/gh credentials, which is a worse
  security and credential story, not a better one. Not worth it.
- **Binding privileged ports (<1024):** moot. Dev ports are 5173+/8000+ by
  design (lines 116-117). Nothing here wants a low port.
- **Writing outside `$HOME`:** the tool has no reason to. Logs in `/tmp` already
  cover the only non-`$HOME` need and need no sudo.

**Verdict: sudo buys nothing worth the friction for this tool.** Keep it
sudo-free and make that a selling point. The only place sudo legitimately appears
is the user's own choice to symlink into `/usr/local/bin`, which the installer
should not do by default.

---

## 3. Configuration ease

The concern: hand-editing a `.config` bash file is not "easy config," especially
for less-technical or non-Linux users.

### How much hand-editing is actually required today?

Less than the concern assumes. `init` already does the heavy lifting:

- It **auto-detects** the stack (Next/Vite/CRA frontends; uv/Django/Rails/
  Express-Nest/Go backends) and **writes** a complete `ataegina.config.sh`
  (`detect_frontend`/`detect_backend`/`emit_config`, lines 317-470).
- It is **interactive by default**: each detected value is offered as a prompt
  default and empty input accepts it (`ask`, lines 309-314; the confirm loop,
  lines 506-515). `--yes` skips prompts for CI.
- For a recognized stack the generated file is runnable as-is; the user confirms
  values at the prompt and never opens the file.

So "you rarely touch the file" is **already substantially true for detected
stacks.** Hand-editing is only needed when: (1) detection fails and the file gets
a commented TODO template (lines 452-457, 464-468), (2) the app reads a different
API-base env var name than the guessed one (the file even flags this, line 449),
or (3) a power user wants the hook escape hatch. (1) and (2) are exactly where a
guided flow helps most.

### Options

**(a) Lean on `init` + an interactive `ataegina config get/set`.** Add a small
subcommand so values can be read and changed without opening the file:
`ataegina config get FRONTEND_CMD`, `ataegina config set FRONTEND_CMD '...'`,
`ataegina config list`. Implementation cost is low because the config is already
just `KEY=VALUE` bash lines that `init` emits; get is a grep, set is a
grep-replace-or-append on the same lines `emit_config` writes. This closes the
"I have to edit bash by hand" gap for the common fixes (wrong dir, wrong env var
name) while keeping the file as the source of truth.

**(b) Keep the declarative bash file, make it maximally forgiving.** Already
mostly true: declarative `*_DIR`/`*_CMD`/`*_ENV` vars mean most users write no
bash, and `*_ENV` accepts both newline- and semicolon-separated assignments
(normalized at lines 151, 164). Continue this: tolerate quoting vari/whitespace,
keep emitting heavy inline comments (it already does).

**(c) A non-bash format (TOML/INI/env) parsed in zero-dep bash.** Assessed and
**rejected.** The config is currently *sourced* (`. "$candidate"`, line 276),
which is what makes `FRONTEND_CMD='npx next dev -p $FRONTEND_PORT'` work: the
`$FRONTEND_PORT` stays literal and expands at run time inside the hook's `sh -c`.
That deferred-expansion behavior, plus the power-user ability to define
`ate_start_*` *functions* in the same file, is the core design. A TOML/INI parser
in pure bash is real code (quoting, arrays, comments, error reporting) and would
**lose** both the deferred `$VAR` expansion and the function escape hatch, or
force reimplementing them. The "config is just sourced bash" simplicity is worth
more than the format change. A plain `.env`-style file buys nothing over what
exists.

### Recommendation

**(a) + (b): keep the sourced-bash file, and add `ataegina config get/set/list`
so the file is essentially never opened by hand.** `init` already gets a new user
to a working config interactively; `config set` covers the handful of post-init
tweaks (rename the API env var, fix a detected dir) without a text editor. This
is the cheapest path to "easy config" and preserves every property that makes the
current design good. Do not introduce TOML/INI.

---

## 4. Licensing and terms

### Is there any EULA / click-through / acceptance flow?

**No, and there should not be.** For an MIT-licensed open-source CLI the norm is:
the `LICENSE` file in the repo is the license, full stop. There is no acceptance
step, no click-through, no "do you agree" prompt. Using, copying, and modifying
are granted by the license text itself (the LICENSE here is standard MIT,
copyright 2026 the maintainer). Adding an acceptance gate would be non-idiomatic and
user-hostile for a dev CLI. Keep it as-is.

### Third-party terms (the real consideration)

ataegina is a thin orchestrator: it shells out to the user's **AI agent**
(`claude -p ...` by default, or `aider`/`codex` via `ATE_AGENT_CMD`, lines 713,
README 380) and optionally to **`gh`** for draft PRs (line 846). Those tools
carry **their own** providers' terms (Anthropic, OpenAI, GitHub, etc.). ataegina
imposes none of its own and should not try to. It is appropriate, and good
hygiene, for the README to add a short note: ataegina runs whatever agent and
tooling you configure, and your use of those is governed by their respective
terms; you are responsible for that usage (including any cost or rate limits the
agent incurs as the dispatcher respawns it). One sentence, not a legal section.

### The `curl | sh` trust/consent surface

`curl | sh` is the convenient install but it is also the only point where a user
is implicitly "trusting" the project. The informed-install story (the closest
thing to "accepting" anything) should be:

- **Publish a checksum** (SHA-256 of the `ataegina` file and of `install.sh`) in
  the README and on the release, so a careful user can verify what they ran.
- **Document the manual path prominently** (section 2 option c) right next to the
  one-liner, so "read it first, then install" is a first-class, equally-documented
  option, not buried. The whole tool is one readable bash file, which is itself
  the strongest trust argument: there is nothing hidden.
- Keep the installer tiny and readable for the same reason.

### Paid/hosted tier

Out of scope now (the tool is local, free, MIT). Flag for later: if a hosted or
paid tier ever exists, that service would carry its own Terms of Service and
possibly a privacy policy, and *that* is when an acceptance flow becomes relevant,
for the service, never retroactively for the MIT CLI.

---

## 5. Updates

### Available mechanisms

- **Manual `git pull`** in a cloned checkout. Works today, zero code. Fine for
  contributors, awkward for users who installed a single file.
- **Re-run the installer** (`curl | sh` again) to re-fetch the latest released
  file. Works once an installer exists; idempotent.
- **`brew upgrade ataegina`** for tap users. Standard, no custom code.
- **Built-in `ataegina update`** self-replace: fetch the latest release of the
  single file, verify checksum, atomically replace the on-disk script
  (download to temp, `chmod +x`, `mv` over itself). Cheap because the tool is one
  file with no build step.
- **Opt-in "newer version available" check** against the GitHub Releases API
  (`/repos/<owner>/ataegina/releases/latest`), comparing the tag against
  `VERSION` (line 41, currently `0.1.0`).

### Recommended UX

Two pieces, both privacy-respecting:

1. **A manual `ataegina update` command.** Fetches the latest release file,
   verifies its published SHA-256, and self-replaces atomically. Print the old
   and new version and a one-line "see CHANGELOG" pointer. This is the primary,
   explicit update path and needs no background anything.

2. **An opt-in update *check* (not auto-update).** Strict rules:
   - **Default OFF.** Enabled only by an explicit `ATE_UPDATE_CHECK=1` (or
     `ataegina config set UPDATE_CHECK 1`).
   - **No telemetry.** It only does an outbound GET to the public releases API;
     it sends no machine info, no usage, nothing identifying beyond a normal
     HTTPS request.
   - **At most once per day.** Stamp a `last-update-check` file in the registry
     dir; skip if checked within 24h.
   - **Offline-safe.** Any network failure is swallowed silently (the tool must
     never block or error because GitHub is unreachable). Same defensive posture
     the dispatcher already takes around `gh` (lines 839-853).
   - **Quiet.** At most one line on a command you were already running:
     `ataegina: 0.2.0 available (you have 0.1.0); run: ataegina update`.

3. **Never silent auto-update.** Developers reasonably hate a CLI that mutates
   itself behind their back, especially one that launches agents that write code
   and open PRs. Updating must always be an explicit `ataegina update` (or
   `brew upgrade`).

**How `--version`/tags/releases tie in:** `--version` already prints `VERSION`
(line 41, 109). Make `VERSION` the single source of truth: tag releases
`v0.2.0`, the check compares the latest tag's version to `VERSION`, and `update`
fetches the file from that tagged release and verifies the release-published
checksum. Keep a `CHANGELOG.md` so every bump is reviewable before a user runs
`update`.

### Should auto-update ever be opt-in-able?

Yes, but cautiously and not in the first pass. If a user genuinely wants it, an
explicit `ATE_AUTO_UPDATE=1` could let the daily check run `update` itself, made
safe by: pinning to a release **tag** (never `main`), only ever moving forward,
showing the changelog delta, and making rollback trivial (since it is one file:
keep the previous version as `ataegina.bak` so rollback is a single `mv`). Even
then, default OFF. The manual command plus the opt-in check covers nearly
everyone; ship those first and treat opt-in auto-update as a later, clearly
gated convenience.

---

## Prioritized list of concrete changes

Effort: S = under an hour, M = a few hours, L = a day+.

**Needs code:**

1. **`install.sh` for one-line install into `~/.local/bin`** (sudo-free; PATH
   hint if missing). Turns install into one command. Effort: S. Priority: high.
2. **Update the README Quickstart** to lead with the sudo-free one-liner and the
   manual download path side by side; demote the `sudo ln -s` form. Effort: S.
   Priority: high. (Doc-only.)
3. **`lsof` fallback shim (`ate_port_pids`/listener probe)** trying `lsof`, then
   `ss`, then `fuser`/`/proc`, so a minimal Linux box works with no extra
   packages. Effort: M. Priority: high (this is the main "fresh Linux" failure).
4. **`ataegina config get/set/list` subcommand** so the config file is rarely
   hand-edited. Effort: M. Priority: medium.
5. **`ataegina update` self-replace** (download latest release file, verify
   SHA-256, atomic `mv`, keep `.bak`). Effort: M. Priority: medium.
6. **Opt-in, off-by-default, once-a-day, offline-safe update check.** Effort: M.
   Priority: medium (do after `update`).
7. **Publish SHA-256 checksums** for the script and installer per release.
   Effort: S (mostly release process). Priority: medium.

**Doc-only:**

8. **Requirements section: spell out `lsof` (and `ss`/`fuser` fallback), and the
   WSL2-vs-Git-Bash Windows guidance.** Effort: S. Priority: high.
9. **One-sentence third-party-terms note** (your configured agent and `gh` carry
   their own providers' terms; you are responsible for that usage, including
   agent cost under respawn). Effort: S. Priority: medium.
10. **`CHANGELOG.md`** to back the version/update story. Effort: S. Priority:
    medium.

**Needs the maintainer's decision:**

- **Homebrew tap: yes/no?** It is the cleanest macOS update path but adds a
  formula to maintain. Decision, then S-M effort.
- **Hosting/owner for `install.sh` and release assets** (the GitHub repo path the
  installer and update check point at). Blocks 1, 5, 6, 7.
- **Whether to ever ship opt-in auto-update** (`ATE_AUTO_UPDATE=1`), or stop at
  manual `update` + opt-in check. Recommendation: ship the latter first, defer
  the former.
- **How hard to chase Git Bash / MSYS2 dispatcher support**, or just document
  "use WSL2." Recommendation: document WSL2, do not invest in MSYS2 detach
  reliability.
