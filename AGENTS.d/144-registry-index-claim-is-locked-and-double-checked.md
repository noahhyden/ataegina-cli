## Claiming a registry index takes the mkdir lock and re-checks

resolve_index claims the lowest free positive index under an atomic mkdir lock (flock is absent on macOS) and re-reads the registry after acquiring it, so a concurrent first up reuses the row instead of duplicating it.
