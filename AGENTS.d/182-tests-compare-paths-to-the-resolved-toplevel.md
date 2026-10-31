## Tests compare paths to the resolved toplevel

On macOS $TMPDIR is a symlink (/var to /private/var) that the VCS resolves, so a raw mktemp path never equals what ataegina records; compare against the `rev-parse --show-toplevel` output instead.
