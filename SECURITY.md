# Security Policy

## Supported versions

ataegina is a single-file script with no released-version branches. Security
fixes land on the latest release; please reproduce on the newest `ataegina`
before reporting (`ataegina --version`, then `ataegina update`).

## Reporting a vulnerability

Please report security issues privately, not in a public issue:

- Preferred: open a private vulnerability report through GitHub Security
  Advisories on this repository (the "Report a vulnerability" button under the
  Security tab).
- Alternatively, email the maintainer (see the GitHub profile of the repository
  owner, `noahhyden`) with `[ataegina security]` in the subject.

Please include the version, your OS and shell (`bash --version`), the exact
commands or config that trigger the issue, and what you expected versus what
happened. We aim to acknowledge a report within a few days. Please give us a
reasonable window to ship a fix before any public disclosure.

## Trust model

ataegina is a developer tool you run on your own machine against repositories you
control. Two properties are worth understanding before you rely on it:

### `ataegina update` and `install.sh` verify a published checksum

Both the self-updater (`ataegina update`) and the installer (`install.sh`)
download the `ataegina` script for a release tag, then, **when a checksum is
published for that tag**, compute its SHA-256 and compare it against the
published `ataegina.sha256` before installing. A mismatch aborts the install with
no changes made; the download is also bash-parse-checked (`bash -n`) before it is
trusted. This is what protects you against a tampered or truncated download.

Caveat: if a release ships **without** a published checksum, both tools print a
`WARN: no published checksum, skipping verification` line and proceed unverified.
That is a deliberate fallback so a checksum-less release still installs, but it
means the integrity guarantee only holds for releases that publish a checksum.
Maintainers should always publish one (see `RELEASE.md`).

The release feed and raw-content base are read over HTTPS from GitHub by default.
No telemetry is sent: the opt-in update check (`ATE_UPDATE_CHECK=1`) makes at
most one GET per 24h to the public GitHub releases API to read the latest tag,
sends no identifiers, and transmits nothing when it is off (the default).

### The config is sourced bash: only run ataegina in repos you trust

`ataegina.config.sh` (and the `$XDG_CONFIG_HOME` / `$ATE_CONFIG` variants) is
**sourced as bash** by every command. The `*_CMD`, `*_ENV`, `DB_URL_TEMPLATE`,
and `DB_CREATE_CMD` / `DB_DROP_CMD` values are command strings evaluated by
`sh -c` or `eval`. This is by design (it is the extension model), but it means a
config file can run arbitrary code.

Consequently: **only run `ataegina` inside a repository whose `ataegina.config.sh`
you trust.** Treat a checked-out config from an untrusted source the same way you
would treat any `Makefile`, `package.json` script, or shell rc you did not write
yourself: read it first. The `ataegina config set` command mitigates one slice of
this by refusing to write non-whitelisted keys and storing values single-quoted,
so it cannot itself inject bash into the file; but it does not, and cannot,
sandbox a config that someone else authored.
