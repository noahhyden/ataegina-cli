# Shared bats helpers for the ataegina suite.
#
# Every test runs against a throwaway HOME-like sandbox: a private temp dir that
# holds the per-test registry, config, log dir, and any throwaway git repos. No
# real servers, databases, or network are ever touched:
#   - ATE_PORT_TOOL=none      so port probes never shell out to lsof/ss/etc.
#   - ATE_REGISTRY_DIR        a temp dir, so the real ~/.config/ataegina is untouched
#   - ATE_UPDATE_CHECK unset  so no command ever reaches the network
#
# Portability: this file and the .bats files avoid GNU-only flags and bash-4
# features, so the suite runs on the macOS system bash 3.2 as well as Linux.

# Absolute path to the ataegina script under test (tests/ lives next to it).
ATE_SCRIPT="$BATS_TEST_DIRNAME/../ataegina"

# ate: invoke the script under test with a clean, network-free, temp registry
# environment. Per-test state lives under $ATE_TMP (set in common_setup). We run
# `bash "$ATE_SCRIPT"` rather than relying on the shebang so the suite is robust
# wherever bash lives, and so coverage of bash-3.2 behavior is explicit on macOS.
ate() {
  ATE_REGISTRY_DIR="$ATE_TMP/registry" \
  ATE_PORT_TOOL="${ATE_PORT_TOOL:-none}" \
  LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
  bash "$ATE_SCRIPT" "$@"
}

# Gates for the tests that go beyond the hermetic unit suite. The default
# `bats tests/` (what CI's fast unit jobs run) stays true to the project ethos —
# no servers, databases, or network — by skipping these unless explicitly enabled:
#
#   ATE_TEST_INTEGRATION=1  run tests that start REAL processes (python/node/go
#                           dev servers, real up/down lifecycle). No network.
#   ATE_TEST_DOCKER=1       run tests that need docker + a live DB engine
#                           (postgres/mysql containers). Implies network.
integration_only() {
  [ "${ATE_TEST_INTEGRATION:-0}" = "1" ] \
    || skip "integration test (real processes) — set ATE_TEST_INTEGRATION=1 to run"
}
docker_only() {
  [ "${ATE_TEST_DOCKER:-0}" = "1" ] \
    || skip "docker integration test — set ATE_TEST_DOCKER=1 to run"
}

# Make a fresh, isolated temp dir for the test and point the registry at it.
common_setup() {
  ATE_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/ate-test.XXXXXX")"
  mkdir -p "$ATE_TMP/registry" "$ATE_TMP/logs"
  # Keep the network completely out of every test.
  unset ATE_UPDATE_CHECK
}

common_teardown() {
  [ -n "${ATE_TMP:-}" ] && rm -rf "$ATE_TMP"
  return 0
}

# Create a throwaway git repo with one commit on `main`, echoing its path. The
# directory layout (frontend/, backend/) gives scope detection something to bite
# on. Git identity is set locally so the suite needs no global git config.
make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "ate test"
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  mkdir -p "$dir/frontend" "$dir/backend"
  echo "fe" > "$dir/frontend/app.js"
  echo "be" > "$dir/backend/server.py"
  echo "root" > "$dir/README.md"
  # The local config is git-ignored in real use; ignore it here too so it never
  # registers as an untracked "other" path that would force scope=both.
  printf 'ataegina.config.sh\n' > "$dir/.gitignore"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "init"
  printf '%s\n' "$dir"
}

# Add a linked worktree to REPO on a new branch, echoing the worktree path.
add_worktree() {
  local repo="$1" name="$2" branch="${3:-$2}"
  local wt="$repo-$name"
  git -C "$repo" worktree add -q -b "$branch" "$wt" >/dev/null 2>&1
  printf '%s\n' "$wt"
}

# Write a config file into a worktree/repo root.
write_config() {
  local dir="$1"; shift
  printf '%s\n' "$@" > "$dir/ataegina.config.sh"
}

# ---------------------------------------------------------------------------
# Safe process reaping for integration tests.
#
# Tests that start REAL processes must reap them, but pattern-based killing is a
# session-killing footgun: `pkill -f "$tag"` with an EMPTY tag becomes
# `pkill -f ""`, whose empty pattern matches EVERY command line — it SIGTERMs
# every process the user owns (shell, editor, desktop). That is exactly how an
# earlier draft of the fake-tool suite froze a laptop.
#
# So ALL reaping/counting goes through these two guarded helpers, and no .bats
# file is allowed to call pkill/pgrep by pattern directly (enforced by
# harness_safety.bats). Both REFUSE an empty or too-short tag, and both target a
# SPECIFIC, unique tag only — never a broad pattern.

# Gating negative assertions for bats. bats runs test bodies under `set -e`, but a
# `!`-prefixed command is EXEMPT from set -e — so a bare `! grep ...` / `! kill -0 ...`
# in the MIDDLE of a test never fails it (it only gates when it happens to be the
# last line, via the return status). That silent false-pass hid a real bug here.
# These return non-zero as NON-negated commands, so set -e turns a violated
# expectation into a real failure wherever they appear in the body.
refute_output_has() { case "${output:-}" in *"$1"*) return 1 ;; *) return 0 ;; esac; }
refute_alive()      { if kill -0 "$1" 2>/dev/null; then return 1; fi; return 0; }

# Reap every process whose command line contains the (specific, non-empty) tag.
# Kills per-PID; refuses an unsafe tag with a loud message and no kill.
ate_reap_tag() {
  local tag="${1:-}" pid
  if [ -z "$tag" ] || [ "${#tag}" -lt 8 ]; then
    echo "ate_reap_tag: refusing unsafe tag '$tag' (empty/short) — not killing anything" >&2
    return 0
  fi
  for pid in $(pgrep -f "$tag" 2>/dev/null || true); do
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill "$pid" 2>/dev/null || true
  done
}

# Count live processes whose command line contains the (specific, non-empty) tag.
# Refuses an unsafe tag by returning 0 (never a bare `pgrep -f ""`).
ate_count_tag() {
  local tag="${1:-}"
  if [ -z "$tag" ] || [ "${#tag}" -lt 8 ]; then echo 0; return 0; fi
  pgrep -f "$tag" 2>/dev/null | grep -c '^[0-9]' || true
}

# True (0) iff some live process whose command line contains $child_tag has a
# PARENT whose command line contains $parent_tag — i.e. a real tree-depth edge.
# Lets a test assert genuine process-tree DEPTH rather than mere breadth. Both
# tags are required non-empty + specific; returns 1 (false) otherwise.
ate_tag_is_child_of() {
  local child_tag="${1:-}" parent_tag="${2:-}" cpid ppid pargs
  { [ -n "$child_tag" ] && [ "${#child_tag}" -ge 8 ] \
    && [ -n "$parent_tag" ] && [ "${#parent_tag}" -ge 8 ]; } || return 1
  for cpid in $(pgrep -f "$child_tag" 2>/dev/null || true); do
    case "$cpid" in ''|*[!0-9]*) continue ;; esac
    ppid="$(ps -o ppid= -p "$cpid" 2>/dev/null | tr -d ' ')"
    [ -n "$ppid" ] || continue
    pargs="$(ps -o args= -p "$ppid" 2>/dev/null || true)"
    case "$pargs" in *"$parent_tag"*) return 0 ;; esac
  done
  return 1
}
