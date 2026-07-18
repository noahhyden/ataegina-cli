#!/usr/bin/env bats
# Regression: concurrent first-`up` (index assignment) must not race two worktrees
# onto the same index. `resolve_index` scanned the registry for the lowest free
# index then appended with no lock, so parallel invocations all picked the same N
# and collided -> identical derived ports AND the same per-worktree DB name, the
# exact collision the tool exists to prevent, in its "fleet of parallel agents"
# use case. Fixed with an atomic mkdir lock (+ double-checked re-read) around the
# scan-append.

load helper

setup()    { common_setup; }
teardown() { common_teardown; }

@test "concurrent index assignment gives every worktree a distinct index" {
  local repo wt i burst n reg total distinct
  n=12
  repo="$(make_repo "$ATE_TMP/repo")"
  # A pool of worktrees (paths have no spaces here, so an index-addressed array is
  # simplest and bash-3.2-safe).
  local pool=()
  for i in $(seq 1 "$n"); do
    wt="$(add_worktree "$repo" "wt$i" "br$i")"
    pool[$i]="$wt"
  done

  # The race window is tiny, so a single burst catches the pre-fix bug only ~60% of
  # the time (measured). Run SEVERAL bursts, clearing the registry before each so all
  # N worktrees re-race from scratch; fail if ANY burst assigns a duplicate index.
  # On fixed (locked) code every burst is deterministically collision-free.
  for burst in 1 2 3 4 5; do
    rm -rf "$ATE_TMP/registry/repos"
    for i in $(seq 1 "$n"); do
      ( cd "${pool[$i]}"; ate ports >/dev/null 2>&1 ) &
    done
    wait
    reg="$(find "$ATE_TMP/registry/repos" -type f ! -name '*.lock' | head -1)"
    [ -n "$reg" ]
    total="$(wc -l < "$reg" | tr -d ' ')"
    distinct="$(cut -f1 "$reg" | sort -u | wc -l | tr -d ' ')"
    if [ "$total" -ne "$n" ] || [ "$distinct" -ne "$n" ]; then
      echo "burst $burst: $total rows, $distinct distinct (expected $n/$n) -> index collision"
      return 1
    fi
  done
}

@test "the registry lock dir is not left behind after assignment" {
  local repo wt
  repo="$(make_repo "$ATE_TMP/repo")"
  wt="$(add_worktree "$repo" wt)"
  cd "$wt"
  run ate ports
  [ "$status" -eq 0 ]
  # No *.lock dir should survive a completed assignment.
  run find "$ATE_TMP/registry/repos" -name '*.lock'
  [ -z "$output" ]
}
