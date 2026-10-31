## The launcher targets bash 3.2

macOS ships bash 3.2 as /bin/bash and the macos-bash32 job asserts the suite passes under it, so no `${var^^}`, no associative arrays, no `declare -n`, no GNU-only flags; windows-gitbash runs a curated process-free subset for the same reason.
