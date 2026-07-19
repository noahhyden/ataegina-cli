# Cutting a release

`ataegina update` and `install.sh` both verify a published SHA-256. That
checksum is computed over the exact `ataegina` file committed at a release tag,
so the only thing a maintainer must get right is: regenerate `ataegina.sha256`
from the same `ataegina` you commit and tag. If they drift, every client that
verifies will abort with a checksum mismatch.

## Checklist

Run from the repo root, working tree clean.

1. **Bump the version.** Edit `VERSION="X.Y.Z"` near the top of `ataegina`.
   This is the single source of truth: `--version` prints it, and the update
   check compares the latest release tag against it.

2. **Regenerate the checksum** from the exact file you are about to commit:

   ```sh
   shasum -a 256 ataegina > ataegina.sha256
   ```

   The file is one line, `HEX  ataegina`. On a Linux box without `shasum`,
   `sha256sum ataegina > ataegina.sha256` produces the same format.

3. **Commit both together.** `ataegina` and `ataegina.sha256` must land in the
   same commit so the digest always matches the script at that revision.

   ```sh
   git add ataegina ataegina.sha256
   git commit -m "Release vX.Y.Z"
   ```

4. **Tag and push.** The tag is what `install.sh` and `update` resolve and fetch
   the per-tag raw files from (`<base>/vX.Y.Z/ataegina`). Pushing the tag is also
   what **triggers the automated release** (steps 5–6 below); the checklist above
   is the only manual part.

   ```sh
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```

5. **The GitHub release is created automatically.** The `.github/workflows/release.yml`
   workflow fires on the `vX.Y.Z` tag: it re-verifies `VERSION == tag` and that
   the committed `ataegina.sha256` matches the script (a mismatch fails the run,
   so a bad release never ships), then publishes the release with `ataegina`,
   `ataegina.sha256`, and `ataegina.1` attached. Notes are taken from the matching
   `## [X.Y.Z]` section of `CHANGELOG.md` when present, else auto-generated.

   To publish by hand instead (e.g. the workflow is disabled):

   ```sh
   gh release create vX.Y.Z ataegina ataegina.sha256 ataegina.1 --title "vX.Y.Z" --notes "..."
   ```

6. **The Homebrew formula is bumped automatically** *when a `HOMEBREW_TAP_TOKEN`
   repo secret is configured* (a PAT with `contents:write` on
   `noahhyden/homebrew-tap`). The `homebrew` job points `Formula/ataegina.rb`'s
   `url` at the new release asset and sets `sha256` to the script's digest, then
   commits and pushes. Without the secret the job self-skips and you must bump the
   formula manually:

   ```sh
   # in noahhyden/homebrew-tap: point url at the new tag, set sha256 to:
   awk '{print $1}' ataegina.sha256
   ```

   `brew style` and `brew audit --formula noahhyden/tap/ataegina` must pass.
   The `curl | sh` and `ataegina update` paths track `latest` automatically and
   need no per-release edit.

## Verify before announcing

Confirm a client would accept the release. From a clean checkout of the tag:

```sh
# digest matches the committed file
shasum -a 256 -c ataegina.sha256

# the version you bumped is what ships
grep '^VERSION=' ataegina
```

Optionally dry-run the installer against the published tag without touching your
own install:

```sh
ATE_REF=vX.Y.Z ATE_BIN=/tmp/ate-relcheck sh install.sh
/tmp/ate-relcheck/ataegina --version
```

## Notes

- The `.sha256` must correspond to the **exact committed `ataegina`**. Any later
  edit to `ataegina` (even whitespace) without regenerating the checksum will
  break verification at that tag.
- If you ever ship a release without a checksum, clients do not fail; `update`
  and `install.sh` print a WARN and proceed unverified. Publishing the checksum
  is what turns that warning into a hard guarantee, so always ship it.
- Never hand-edit a tagged `ataegina` in place. Cut a new patch release instead.
