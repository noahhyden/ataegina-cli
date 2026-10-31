## A worktree with no config falls back to the primary checkout's

ataegina.config.sh is untracked and git does not copy it into a linked worktree, so config search tries $ATE_CONFIG, the worktree, the PRIMARY checkout, then $REGISTRY_DIR; drop the fallback and `up` fails with no backend configured.
