#!/bin/sh
# ataegina installer. One command, sudo-free, single readable file.
#
#   curl -fsSL https://raw.githubusercontent.com/noahhyden/ataegina-cli/<ref>/install.sh | sh
#
# What it does: resolves the latest published release tag, downloads that tag's
# `ataegina` script, verifies its SHA-256 (when a checksum is published),
# bash-parse-checks it, and installs it to ~/.local/bin/ataegina (chmod +x). No
# sudo, ever. If the install dir is not on PATH it prints the exact line to add
# to your shell rc; it never edits rc files for you.
#
# It is deliberately small so you can read it before running it. The whole tool
# is one bash file with no build step; there is nothing hidden here.
#
# Overridable via env (mirrors the conventions `ataegina update` uses, so this
# is testable against a local file:// stub):
#   ATE_RELEASES_URL  the "latest release" JSON feed (default: GitHub API)
#   ATE_RAW_BASE      base for raw files; per-tag script is <base>/<tag>/ataegina
#   ATE_REF           pin a specific ref/tag to install (skips release lookup)
#   ATE_DEFAULT_REF   fallback ref when no release is found (default: main)
#   ATE_BIN / PREFIX  install dir (default: ~/.local/bin)
#   GH_TOKEN          optional GitHub token, sent as a bearer to the feed
#
# POSIX sh; no bashisms, no GNU-only flags.

set -eu

REPO_SLUG="noahhyden/ataegina-cli"
RELEASES_URL="${ATE_RELEASES_URL:-https://api.github.com/repos/${REPO_SLUG}/releases/latest}"
RAW_BASE="${ATE_RAW_BASE:-https://raw.githubusercontent.com/${REPO_SLUG}}"
DEFAULT_REF="${ATE_DEFAULT_REF:-main}"

# Install dir: ATE_BIN wins, then PREFIX/bin, then ~/.local/bin.
if [ -n "${ATE_BIN:-}" ]; then
  BIN_DIR="$ATE_BIN"
elif [ -n "${PREFIX:-}" ]; then
  BIN_DIR="$PREFIX/bin"
else
  BIN_DIR="$HOME/.local/bin"
fi

say()  { printf '[ate-install] %s\n' "$*"; }
err()  { printf '[ate-install] %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# --- prerequisites -----------------------------------------------------------

# A fetcher: curl, else wget. Echoes the tool name; dies if neither exists.
FETCHER=""
if command -v curl >/dev/null 2>&1; then
  FETCHER="curl"
elif command -v wget >/dev/null 2>&1; then
  FETCHER="wget"
else
  die "need curl or wget to download; neither found."
fi

# bash is needed to parse-check the downloaded script (it is a bash program).
command -v bash >/dev/null 2>&1 || die "need bash to verify the downloaded script; not found."

# Fetch URL ($1) to stdout. Short timeout ($2, seconds; default 20). Returns the
# fetch tool's exit code (nonzero on any network/HTTP error). file:// works with
# both curl and wget, which is what the local-stub tests rely on.
fetch() {
  url="$1"
  timeout="${2:-20}"
  if [ "$FETCHER" = "curl" ]; then
    if [ -n "${GH_TOKEN:-}" ]; then
      curl -fsSL --max-time "$timeout" -H "Authorization: Bearer $GH_TOKEN" "$url" 2>/dev/null
    else
      curl -fsSL --max-time "$timeout" "$url" 2>/dev/null
    fi
  else
    if [ -n "${GH_TOKEN:-}" ]; then
      wget -q -T "$timeout" --header="Authorization: Bearer $GH_TOKEN" -O - "$url"
    else
      wget -q -T "$timeout" -O - "$url"
    fi
  fi
}

# Compute the SHA-256 of a file ($1), printing just the lowercase hex digest.
# Detects shasum (-a 256) then sha256sum. Nonzero if neither is available.
compute_sha256() {
  f="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
  else
    return 1
  fi
}

# --- resolve which ref to install --------------------------------------------

# ATE_REF pins a ref explicitly. Otherwise resolve the latest release tag from
# the feed; if that fails (no release yet, or unreachable), fall back to
# DEFAULT_REF so a repo without releases still installs from its default branch.
resolve_ref() {
  if [ -n "${ATE_REF:-}" ]; then
    printf '%s\n' "$ATE_REF"
    return 0
  fi
  body="$(fetch "$RELEASES_URL" 20 || true)"
  if [ -n "$body" ]; then
    tag="$(printf '%s\n' "$body" \
      | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -n1 \
      | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
    if [ -n "$tag" ]; then
      printf '%s\n' "$tag"
      return 0
    fi
  fi
  printf '%s\n' "$DEFAULT_REF"
}

REF="$(resolve_ref)"
if [ -n "${ATE_REF:-}" ]; then
  say "installing ref $REF (pinned)"
elif [ "$REF" = "$DEFAULT_REF" ]; then
  say "no release found; installing from $REF"
else
  say "latest release: $REF"
fi

# --- download into a temp working dir ----------------------------------------

# A self-cleaning temp dir so a failure never leaves a partial install behind.
TMP_DIR="$(mktemp -d 2>/dev/null)" || die "could not create a temp dir."
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

TMP_SCRIPT="$TMP_DIR/ataegina"
TMP_SHA="$TMP_DIR/ataegina.sha256"

if ! fetch "$RAW_BASE/$REF/ataegina" 60 > "$TMP_SCRIPT" || [ ! -s "$TMP_SCRIPT" ]; then
  err "could not download $RAW_BASE/$REF/ataegina"
  err "the repo may still be private (or the ref is wrong, or the network is down)."
  err "no changes were made. To install manually once you have access, see:"
  err "  https://github.com/${REPO_SLUG}#install"
  exit 1
fi

# --- verify SHA-256 (when published) -----------------------------------------

if fetch "$RAW_BASE/$REF/ataegina.sha256" 30 > "$TMP_SHA" 2>/dev/null && [ -s "$TMP_SHA" ]; then
  want_sha="$(awk '{print $1; exit}' "$TMP_SHA")"
  got_sha="$(compute_sha256 "$TMP_SCRIPT")" || got_sha=""
  if [ -z "$got_sha" ]; then
    die "no shasum/sha256sum tool to verify the download; aborting (nothing installed)."
  fi
  if [ "$want_sha" != "$got_sha" ]; then
    err "CHECKSUM MISMATCH"
    err "  expected $want_sha"
    err "  got      $got_sha"
    die "aborting; nothing installed."
  fi
  say "checksum verified"
else
  say "WARN: no published checksum, skipping verification"
fi

# --- parse-check before trusting it ------------------------------------------

if ! bash -n "$TMP_SCRIPT" 2>/dev/null; then
  die "the downloaded script does not parse (bash -n failed); aborting, nothing installed."
fi

# --- install -----------------------------------------------------------------

mkdir -p "$BIN_DIR" 2>/dev/null || die "could not create install dir $BIN_DIR"
DEST="$BIN_DIR/ataegina"
chmod +x "$TMP_SCRIPT" 2>/dev/null || true
if ! cp "$TMP_SCRIPT" "$DEST" 2>/dev/null; then
  die "could not write $DEST (check permissions); nothing installed."
fi
chmod +x "$DEST" 2>/dev/null || true

# Resolve the installed version straight from the file (VERSION="x.y.z").
INSTALLED_VER="$(sed -n 's/^VERSION="\{0,1\}\([0-9][^"]*\)"\{0,1\}.*/\1/p' "$DEST" | head -n1)"
[ -n "$INSTALLED_VER" ] || INSTALLED_VER="(unknown)"

say "installed ataegina $INSTALLED_VER to $DEST"

# --- man page (best-effort; never fatal) -------------------------------------

# Install the man page alongside the script so `man ataegina` works. This is
# strictly optional: any failure (page not published for this ref, no writable
# man dir) is a soft note, never an error — the tool itself is already installed.
# Man dir: ATE_MAN wins, then PREFIX/share/man, then ~/.local/share/man.
if [ -n "${ATE_MAN:-}" ]; then
  MAN_DIR="$ATE_MAN"
elif [ -n "${PREFIX:-}" ]; then
  MAN_DIR="$PREFIX/share/man/man1"
else
  MAN_DIR="$HOME/.local/share/man/man1"
fi
TMP_MAN="$TMP_DIR/ataegina.1"
if fetch "$RAW_BASE/$REF/ataegina.1" 30 > "$TMP_MAN" 2>/dev/null && [ -s "$TMP_MAN" ]; then
  if mkdir -p "$MAN_DIR" 2>/dev/null && cp "$TMP_MAN" "$MAN_DIR/ataegina.1" 2>/dev/null; then
    say "installed man page to $MAN_DIR/ataegina.1"
  else
    say "note: could not write the man page to $MAN_DIR (skipped)"
  fi
fi

# --- PATH hint (never edits rc files) ----------------------------------------

# Is BIN_DIR on PATH? Compare it against each PATH element exactly.
on_path=0
old_ifs="$IFS"
IFS=:
for d in $PATH; do
  if [ "$d" = "$BIN_DIR" ]; then on_path=1; break; fi
done
IFS="$old_ifs"

if [ "$on_path" -ne 1 ]; then
  # Detect the user's shell rc to name the right file (zsh vs bash). Best-effort.
  shell_name="$(basename "${SHELL:-}" 2>/dev/null || true)"
  case "$shell_name" in
    zsh)  rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *)    rc="your shell's startup file" ;;
  esac
  say "$BIN_DIR is not on your PATH yet. Add this line to $rc, then restart your shell:"
  printf '\n    export PATH="%s:$PATH"\n\n' "$BIN_DIR"
fi

say "run: ataegina --help"
