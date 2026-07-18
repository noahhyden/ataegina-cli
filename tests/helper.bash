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
