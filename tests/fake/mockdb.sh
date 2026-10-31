#!/usr/bin/env bash
# Fake DB CLI: args are $1 action, $2 log file, $3 exit code (default 0); records "<action> <ATE_DB_NAME>" so tests can assert `up` stays non-fatal.
set -u
action="${1:-?}"
logfile="${2:-}"
code="${3:-0}"
[ -n "$logfile" ] && printf '%s %s\n' "$action" "${ATE_DB_NAME:-NONE}" >> "$logfile"
exit "$code"
