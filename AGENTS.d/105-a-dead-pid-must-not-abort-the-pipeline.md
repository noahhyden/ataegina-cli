## A dead pid must not abort a pipefail pipeline

`ps -p` on a dead pid exits non-zero, so under pipefail the command substitution fails and set -e aborts down before it reaps the port holder; ate_pid_starttime tolerates it and yields an empty string.
