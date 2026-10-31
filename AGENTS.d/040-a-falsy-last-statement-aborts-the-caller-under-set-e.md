## A falsy last statement aborts the caller under set -e

ataegina runs under `set -euo pipefail`, so a function ending on a failed test returns 1 and set -e kills its caller mid-command; emit_config and cmd_up each carry an explicit return for exactly this, so end any new function on an explicit status.
