## Scope precedence is flag, primary, declared, auto, fallback

resolve_scope picks the first hit of --scope, index 0 (always both), a scope: line in $ATE_TASK_FILE, auto-detect (off when ATE_SCOPE_AUTO=0), then both; only the auto-detected none is nudged to both.
