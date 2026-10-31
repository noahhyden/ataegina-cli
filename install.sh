#!/bin/sh
# ataegina installer: sudo-free, verifies SHA-256, installs to ~/.local/bin; env knobs ATE_RELEASES_URL/ATE_RAW_BASE/ATE_REF/ATE_BIN/PREFIX; POSIX sh only.

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

# Fetch URL ($1) to stdout with timeout ($2, default 20s); returns the fetch tool's nonzero exit on any error.
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

# Print the lowercase SHA-256 hex of file $1 via shasum or sha256sum; nonzero if neither exists.
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

# ATE_REF pins a ref; otherwise use the latest release tag, falling back to DEFAULT_REF when none resolves.
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

# Man page install is optional: any failure is a soft note, never an error.
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
