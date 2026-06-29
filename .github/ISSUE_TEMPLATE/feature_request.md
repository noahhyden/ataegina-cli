---
name: Feature request
about: Suggest an idea or improvement for ataegina
title: "[feature] "
labels: ["type: feature", "status: needs triage"]
assignees: ''
---

## The problem

What are you trying to do that ataegina makes hard or impossible today?

## Proposed solution

What you would like to see. If it touches the CLI, sketch the command and output.

## Alternatives considered

Other approaches, including doing it in your own config hooks
(`ate_start_*` / `ate_doctor` / `*_CMD`) instead of in the core script.

## Fit with the project ethos

ataegina is deliberately a single, zero-dependency, bash-3.2-compatible script
with no build step, and it keeps the index / port / registry contract stable.
Please note how your request fits within that:

- [ ] No new runtime dependency (no package manager, no compiled step)
- [ ] Stays bash-3.2-safe and avoids GNU-only tool flags (must run on macOS
      system bash as-is)
- [ ] Does not change the stable index assignment, port derivation, or registry
      format (or, if it must, explains why and how migration works)
- [ ] Stays generic (no project-, company-, or stack-specific assumptions in the
      core script)

## Anything else

Context, links, or prior art.
