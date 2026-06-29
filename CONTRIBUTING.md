# Contributing

Thanks for taking a look. ataegina is deliberately small: vanilla bash, no
build step, no dependencies beyond `git` and `awk` plus a port backend (`lsof`,
or the `ss`/`fuser`/`proc` fallback). Keep it that way.

## Ground rules

- **Zero dependencies.** No package manager, no runtime, no compiled step. If a
  change needs a dependency, it probably belongs in your config hooks, not here.
- **bash 3.2 compatible.** Target plain `bash` and stay 3.2-safe: no associative
  arrays, `mapfile`/`readarray`, `${var^^}`, process substitution, or
  here-strings, and no GNU-only tool flags (the script must run on the macOS
  system bash as-is). Run `shellcheck ataegina` before opening a PR.
- **`install.sh` stays POSIX `sh`.** It is a `curl | sh` target: keep it small,
  readable, and free of bashisms.
- **Keep the algorithm intact.** Stable index assignment, port derivation, the
  registry format, and `$PWD`-anchoring are the contract. Changing them breaks
  existing registries; propose it explicitly in an issue first.
- **Stay generic.** No project-, company-, or stack-specific assumptions in the
  core script. Project specifics live in `ataegina.config.sh`.

## Workflow

1. Open an issue describing the change before large PRs.
2. One logical change per PR. Small is good.
3. Update the README and `ataegina.config.example.sh` if you change the CLI,
   the config keys, or the exported hook environment.
4. Cutting a release? Follow [`RELEASE.md`](RELEASE.md) so the published
   `ataegina.sha256` matches the committed `ataegina` (clients verify it).

## Testing

Run the bats suite before sending a change: `bats tests/`. It is hermetic
(driven by a temp registry and `ATE_PORT_TOOL=none`, so it needs no servers,
databases, or network) and runs on macOS system bash 3.2 and on Linux; CI runs
it on both. `shellcheck ataegina` should also stay clean (see the exclusion list
in `.github/workflows/ci.yml`).

For anything the suite does not cover, a quick manual pass still helps: create a
couple of throwaway worktrees, run `ataegina up`, `ports`, `list`, and `prune`,
and confirm indices and ports are stable and recycled correctly.
