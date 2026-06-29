---
name: Bug report
about: Something in ataegina does not behave as documented
title: "[bug] "
labels: bug
assignees: ''
---

## What happened

A clear description of the bug.

## What you expected

What you expected to happen instead.

## Steps to reproduce

The exact commands, ideally from a throwaway repo. For example:

```sh
git init demo && cd demo && git commit --allow-empty -m init
ataegina init --yes
ataegina up
ataegina ports
```

## Environment

- `ataegina --version`:
- OS / distro:
- Shell (`bash --version`):
- Port tool reported by `ataegina doctor` (lsof / ss / fuser / proc / none):
- How installed (install.sh / manual / update):

## doctor output

The output of `ataegina doctor` from the affected worktree (it is read-only):

```
paste here
```

## Relevant config

The relevant parts of `ataegina.config.sh` (redact anything sensitive):

```sh
paste here
```

## Anything else

Logs, screenshots, or notes that might help.
