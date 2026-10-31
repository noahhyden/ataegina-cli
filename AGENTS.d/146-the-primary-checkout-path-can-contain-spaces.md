## Take the whole porcelain worktree line, never awk field 2

The primary path is everything after the "worktree " prefix, because repo paths can contain spaces and awk {print $2} truncates them, making TREE differ from PRIMARY and losing index 0 and its shared DB.
