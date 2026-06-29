## What and why

What this change does, and the problem it solves. Link any related issue
(`Closes #NNN`).

## How to verify

The commands a reviewer can run to see it work, plus what they should observe.

## Checklist

- [ ] One logical change (small is good).
- [ ] `shellcheck ataegina` is clean (the CI runs it with the project's
      documented exclusions; do not add new findings).
- [ ] `install.sh` stays POSIX `sh` (no bashisms) if touched.
- [ ] Stays bash-3.2-safe and free of GNU-only tool flags (must run on macOS
      system bash as-is): no associative arrays, `mapfile`/`readarray`,
      `${var^^}`, process substitution, or here-strings.
- [ ] No new runtime dependency (bats-core as a dev/test dependency is fine).
- [ ] The index assignment, port derivation, registry format, and
      `$PWD`-anchoring contract are unchanged (or the change is justified and
      migration is described).
- [ ] Tests added or updated under `tests/`, and `bats tests/` passes locally.
- [ ] README and `ataegina.config.example.sh` updated if the CLI, config keys,
      or exported hook environment changed.
- [ ] `CHANGELOG.md` updated under `## [Unreleased]`.
- [ ] Cutting a release? Followed `RELEASE.md` so `ataegina.sha256` matches the
      committed `ataegina`.

## Notes

Anything else reviewers should know (trade-offs, follow-ups, things you are
unsure about).
