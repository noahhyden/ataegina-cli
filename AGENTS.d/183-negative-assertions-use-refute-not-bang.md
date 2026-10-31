## Negative assertions use refute, never a bare !

A statement starting with `!` is exempt from set -e inside a bats test, so a failing negative assertion is a silent no-op mid-test; use refute from helper.bash.
