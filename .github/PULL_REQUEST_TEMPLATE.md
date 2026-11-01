## What and why

What this change does, and the problem it solves. Link any related issue
(`Closes #NNN`).

## How to verify

The commands a reviewer can run to see it work, plus what they should observe.

## Checklist

CI already enforces shellcheck, bats on Linux + macOS, bash 3.2, and the
checksum. These are the ones it cannot check — see
[CONTRIBUTING.md](../CONTRIBUTING.md) for the ground rules.

- [ ] One logical change (small is good).
- [ ] No new runtime dependency.
- [ ] The index assignment, port derivation, registry format, and
      `$PWD`-anchoring contract are unchanged (or the change is justified and
      migration is described).
- [ ] README and `ataegina.config.example.sh` updated if the CLI, config keys,
      or exported hook environment changed.
- [ ] `CHANGELOG.md` updated under `## [Unreleased]`.

## Notes

Anything else reviewers should know (trade-offs, follow-ups, things you are
unsure about).
