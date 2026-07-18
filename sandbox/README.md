# sandbox — an isolated playground for `ataegina`

An interactive companion to the automated tests in [`../tests/`](../tests/). It
spins up a real full-stack **mock** repo (frontend + backend that are real python
listeners) plus two linked worktrees, wired to a **fully isolated** ataegina
environment, so you can drive `up` / `down` / `ports` / `db` / `logs` / `move`
against real processes and see the collision-free ports + per-worktree databases
first-hand — without touching your real `~/.config/ataegina` or `/tmp/ate-wt*`.

Everything generated lives under `sandbox/.work/` and is **gitignored**; the repo
only carries the generator (`setup.sh`). This is why the mock isn't committed as
data: the mock repos are throwaway git checkouts with transient registry/log state.

## Use

```sh
bash sandbox/setup.sh          # (re)build the mock stack under sandbox/.work
source sandbox/.work/env.sh    # isolated env + an `ate` shell function

cd sandbox/.work/mock          # primary checkout — index 0, ports 39000/38000, DB "shop"
ate up                         # start frontend + backend on this slot
ate ports
curl -s localhost:38000 ; echo # backend echoes its injected DATABASE_URL
ate down

cd sandbox/.work/mock-a        # linked worktree — index 1, ports 39001/38001, DB "shop_wt1"
ate up                         # collision-free: its own ports AND its own database
```

Reset to a clean stack anytime with `bash sandbox/setup.sh`; remove it entirely
with `rm -rf sandbox/.work`.

## What it demonstrates

- **Collision-free ports** — each worktree derives `FRONT_PORT_BASE+N` / `BACK_PORT_BASE+N`.
- **Per-worktree databases** — the primary keeps the shared `shop`; each worktree N
  gets its own `shop_wt{N}` (sqlite here), injected as `DATABASE_URL`.
- **Config inheritance** — the (gitignored) `ataegina.config.sh` in the primary is
  inherited by the linked worktrees automatically.
- **Real process lifecycle** — `up` detaches real servers; `down` reaps the whole tree.

For the reproducible, CI-run versions of these scenarios (including real
postgres/mysql/mariadb via docker, and go/node/ruby backends), see the integration
tests under `tests/` and the tiers documented in [`../CONTRIBUTING.md`](../CONTRIBUTING.md).
