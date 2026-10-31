#!/usr/bin/env bats
# Static safety lint for the test HARNESS itself (runs in the hermetic unit suite;
# starts no processes, binds no ports). It exists because an earlier draft of the
# fake-tool suite froze a laptop: a teardown reaped with `pkill -f "$TAG"` while
# TAG was assigned only later in setup(), AFTER the skip guards. bats runs
# teardown for skipped tests too, so on every skip the pattern was empty — and an
# empty `-f` pattern matches EVERY command line, SIGTERMing the user's whole
# session. These checks make that class of bug fail CI instead of the machine.

load helper

# Any variable used as a `-f` pattern to a process killer must be assigned at FILE SCOPE so teardown sees it non-empty even after a skip.
@test "harness safety: every variable pattern-kill uses a file-scope (never-empty) tag" {
  local f line var offenders=""
  for f in "$BATS_TEST_DIRNAME"/*.bats; do
    # Strip whole-line comments first so prose mentioning the killers is ignored.
    while IFS= read -r line; do
      var="$(printf '%s\n' "$line" \
        | sed -nE 's/.*(kill|grep)[[:space:]]+-f[[:space:]]+"\$([A-Za-z_][A-Za-z_0-9]*)".*/\2/p')"
      [ -n "$var" ] || continue
      # Assigned at file scope (line begins with VAR=) -> provably set in teardown.
      grep -qE "^${var}=" "$f" && continue
      offenders="$offenders $(basename "$f"):\$$var"
    done < <(grep -v '^[[:space:]]*#' "$f")
  done
  if [ -n "$offenders" ]; then
    echo "unguarded variable pattern-kill(s) — assign the tag at file scope, or reap via ate_reap_tag:$offenders"
    false
  fi
}

# The shared reaper/counter helpers must refuse an empty or too-short tag so an empty pattern never reaches the killer.
@test "harness safety: the reaper/counter helpers refuse an empty/short tag" {
  local h="$BATS_TEST_DIRNAME/helper.bash"
  grep -q 'ate_reap_tag()'  "$h"
  grep -q 'ate_count_tag()' "$h"
  # Each guarded helper carries the length check that blocks an empty/short tag.
  [ "$(grep -c '"${#tag}" -lt 8' "$h")" -ge 2 ]
}

# fake_tool.bats must not call the process killers by pattern directly; it routes through the guarded helpers.
@test "harness safety: fake_tool.bats never calls the killers by pattern directly" {
  local f="$BATS_TEST_DIRNAME/fake_tool.bats"
  run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -nE '(kill|grep)[[:space:]]+-f'"
  [ "$status" -ne 0 ]   # no matches -> grep exits non-zero -> good
}

# Rule: no test may use a `!`-prefixed command as an assertion. bats runs bodies
# under set -e, but a `!`-prefixed command is EXEMPT from it — so `! grep ...`
# mid-body is a silent no-op that never fails the test. Negative assertions must go
# through the gating helpers (refute / refute_output_has / refute_alive) instead.
@test "harness safety: no test uses a set -e-exempt '!'-prefixed assertion" {
  local f offenders=""
  for f in "$BATS_TEST_DIRNAME"/*.bats; do
    # Anchor at line start: `while ! cond` puts the `!` mid-line, so this targets only bare assertions.
    if grep -nE '^[[:space:]]*![[:space:]]' "$f" >/dev/null 2>&1; then
      offenders="$offenders $(basename "$f")"
    fi
  done
  if [ -n "$offenders" ]; then
    echo "'!'-prefixed assertions (use refute/refute_output_has/refute_alive):$offenders"
    false
  fi
}
