#!/usr/bin/env bash
# mockdb.sh — a fake database CLI for probing ataegina's DB create/drop hooks
# (ate_db_ensure / ate_db_create / ate_db_drop) without a real engine or docker.
#
# ataegina runs DB_CREATE_CMD / DB_DROP_CMD via `sh -c` with ATE_DB_NAME exported.
# Point those at this script to (a) record exactly what name each hook was called
# with and (b) force a chosen exit code — so a test can simulate a broken/missing
# engine and assert `up` stays NON-FATAL (a dead DB must not block the dev stack).
#
# Args: $1 = action label (create|drop|...)   recorded verbatim
#       $2 = log file       appended with "<action> <ATE_DB_NAME>" (skip if empty)
#       $3 = exit code      default 0; set 1 to simulate a failing engine
#
# Usage in a config:
#   DB_CREATE_CMD='bash "tests/fake/mockdb.sh" create "/path/log" 1'
set -u
action="${1:-?}"
logfile="${2:-}"
code="${3:-0}"
[ -n "$logfile" ] && printf '%s %s\n' "$action" "${ATE_DB_NAME:-NONE}" >> "$logfile"
exit "$code"
