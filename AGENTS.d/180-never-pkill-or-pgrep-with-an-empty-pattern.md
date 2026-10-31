## Never pkill or pgrep -f with an empty or short pattern

A `pkill -f "$VAR"` with an empty VAR once froze a laptop; use the guarded ate_reap_tag/ate_count_tag helpers, and assign teardown variables at file scope so a skip in setup() cannot leave them empty.
