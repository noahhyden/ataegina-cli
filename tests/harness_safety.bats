#!/usr/bin/env bats
# Static safety lint for the test HARNESS itself (runs in the hermetic unit suite;
# starts no processes, binds no ports). It exists because an earlier draft of the
# fake-tool suite froze a laptop: a teardown reaped with `pkill -f "$TAG"` while
# TAG was assigned only later in setup(), AFTER the skip guards. bats runs
# teardown for skipped tests too, so on every skip the pattern was empty — and an
# empty `-f` pattern matches EVERY command line, SIGTERMing the user's whole
# session. These checks make that class of bug fail CI instead of the machine.

load helper

# Rule: any variable used as a `-f` pattern to the process killers must be assigned
# at FILE SCOPE (column 0), which guarantees it is non-empty in teardown regardless
# of whether setup() bailed out on a skip. A var assigned only inside setup() (the
# exact original bug) is rejected. Reaping via the guarded ate_reap_tag/ate_count_tag
# helpers is always fine — they refuse an empty/short tag themselves.
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

# Rule: the shared reaper/counter helpers must refuse an empty or too-short tag, so
# a broad empty-pattern match can never reach the killer even if a caller passes "".
@test "harness safety: the reaper/counter helpers refuse an empty/short tag" {
  local h="$BATS_TEST_DIRNAME/helper.bash"
  grep -q 'ate_reap_tag()'  "$h"
  grep -q 'ate_count_tag()' "$h"
  # Each guarded helper carries the length check that blocks an empty/short tag.
  [ "$(grep -c '"${#tag}" -lt 8' "$h")" -ge 2 ]
}

# Rule: the fake-tool suite (the file that carried the original bug) must not call
# the process killers by pattern directly — it routes everything through the
# guarded helpers. This keeps the dangerous primitive in exactly one audited place.
@test "harness safety: fake_tool.bats never calls the killers by pattern directly" {
  local f="$BATS_TEST_DIRNAME/fake_tool.bats"
  run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -nE '(kill|grep)[[:space:]]+-f'"
  [ "$status" -ne 0 ]   # no matches -> grep exits non-zero -> good
}
