---
applies_to:
  - ".github/scripts/check_one_line_comments.py"
  - ".github/one-line-comment-baseline.json"
---
## Explanation in code is capped at ONE line; the rest belongs in AGENTS.d

check_one_line_comments.py ratchets bash, yaml and python against a per-file baseline that may only shrink: a run of standalone comment lines is one line, a python docstring is one line, and the fix for a longer one is an AGENTS.d rule.
