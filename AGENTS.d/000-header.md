# AGENTS.d

One rule per file. A rule is a trap and its consequence, in one line of at most 255 characters — `.github/scripts/check_agents_rule_length.py` enforces it.

Long-form reasoning belongs in `docs/`, not in an agent's always-loaded context. Code comments are capped at one line by `.github/scripts/check_one_line_comments.py`; a comment that wants a paragraph wants a rule here instead.
