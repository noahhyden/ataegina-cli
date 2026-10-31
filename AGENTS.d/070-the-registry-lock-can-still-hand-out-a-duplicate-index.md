## The registry lock can still hand out a duplicate index

resolve_index guards its claim with an mkdir mutex but gives up after a ~10s spin and proceeds anyway, so a loaded runner can let two worktrees take one index — the collision this tool exists to prevent. tests/concurrency.bats fails intermittently on it.
