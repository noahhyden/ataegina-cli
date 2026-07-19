#!/usr/bin/env bats
# `ataegina update` (self-update) — happy path + every error branch, driven fully
# locally with file:// release stubs (no network). These run the SOURCE script (so
# coverage is attributed to it), with a WRITABLE copy on PATH as `ataegina` so
# ate_self_path targets the copy and the real source is never replaced.

load helper

setup() {
  common_setup
  CUR="$(sed -n 's/^VERSION="\{0,1\}\([0-9][^"]*\)"\{0,1\}.*/\1/p' "$ATE_SCRIPT" | head -n1)"
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || skip "need curl or wget for file:// fetch"
  STUB="$ATE_TMP/stub"
  BIN="$ATE_TMP/bin"
  mkdir -p "$STUB" "$BIN"
  # The install target ate_update will replace: a writable copy on PATH as `ataegina`.
  cp "$ATE_SCRIPT" "$BIN/ataegina"; chmod +x "$BIN/ataegina"
}
teardown() { common_teardown; }

# Advertise $1 as the latest tag in the feed stub.
feed_tag() { printf '{"tag_name": "%s"}\n' "$1" > "$STUB/latest.json"; }
# Serve a release artifact for tag $1 with body from file $2 (default: a copy of the
# source, which parses). Also publishes a matching sha256 unless $3 == "nosha".
serve_release() {
  local tag="$1" body="${2:-$ATE_SCRIPT}" sha="${3:-}"
  mkdir -p "$STUB/$tag"
  cp "$body" "$STUB/$tag/ataegina"
  if [ "$sha" != "nosha" ]; then
    if command -v shasum >/dev/null 2>&1; then ( cd "$STUB/$tag" && shasum -a 256 ataegina > ataegina.sha256 )
    elif command -v sha256sum >/dev/null 2>&1; then ( cd "$STUB/$tag" && sha256sum ataegina > ataegina.sha256 ); fi
  fi
}
# Run the SOURCE `update` against the stubs, with the copy on PATH.
run_update() {
  run env PATH="$BIN:$PATH" \
    ATE_RELEASES_URL="file://$STUB/latest.json" \
    ATE_RAW_BASE="file://$STUB" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    bash "$ATE_SCRIPT" update
}

@test "update: older published tag -> already on latest" {
  feed_tag "v0.0.1"; serve_release "v0.0.1"
  run_update
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already on the latest version"
}

@test "update: same version -> already on latest" {
  feed_tag "v$CUR"; serve_release "v$CUR"
  run_update
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already on the latest version"
}

@test "update: newer tag with a matching checksum installs (backup + replace)" {
  feed_tag "v99.0.0"; serve_release "v99.0.0"
  run_update
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE "updated .* -> v99\.0\.0"
  echo "$output" | grep -qi "rollback if needed"
  [ -f "$BIN/ataegina.bak" ]                     # backup was written
}

@test "update: newer tag with NO published checksum warns but still installs" {
  feed_tag "v99.0.0"; serve_release "v99.0.0" "$ATE_SCRIPT" "nosha"
  run_update
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "no published checksum, skipping verification"
  echo "$output" | grep -qiE "updated .* -> v99\.0\.0"
}

@test "update: checksum MISMATCH aborts and does not install" {
  feed_tag "v99.0.0"; serve_release "v99.0.0"
  printf '%s  ataegina\n' "deadbeef" > "$STUB/v99.0.0/ataegina.sha256"   # wrong hash
  run_update
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "CHECKSUM MISMATCH"
}

@test "update: a download that does not parse as bash aborts" {
  printf 'this is ( not valid bash\n' > "$ATE_TMP/badscript"
  feed_tag "v99.0.0"; serve_release "v99.0.0" "$ATE_TMP/badscript" "nosha"
  run_update
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "does not parse"
}

@test "update: an empty downloaded script aborts" {
  : > "$ATE_TMP/empty"
  feed_tag "v99.0.0"; serve_release "v99.0.0" "$ATE_TMP/empty" "nosha"
  run_update
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "empty file"
}

@test "update: a missing release artifact (download fails) aborts, install untouched" {
  feed_tag "v99.0.0"   # advertise the tag but serve NO v99.0.0/ataegina
  run_update
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "failed to download"
}

@test "update: an unreachable release feed reports it and aborts" {
  # Point the feed at a file that does not exist.
  run env PATH="$BIN:$PATH" \
    ATE_RELEASES_URL="file://$STUB/nope.json" \
    ATE_RAW_BASE="file://$STUB" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    bash "$ATE_SCRIPT" update
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "could not reach the release feed"
}

@test "update: a non-writable install target aborts before fetching" {
  feed_tag "v99.0.0"; serve_release "v99.0.0"
  chmod -w "$BIN/ataegina"
  run_update
  chmod +w "$BIN/ataegina"                       # restore so teardown can clean up
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not writable"
}

@test "update: GH_TOKEN is sent as a bearer on the fetch" {
  feed_tag "v0.0.1"; serve_release "v0.0.1"
  run env PATH="$BIN:$PATH" GH_TOKEN=sometoken \
    ATE_RELEASES_URL="file://$STUB/latest.json" ATE_RAW_BASE="file://$STUB" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    bash "$ATE_SCRIPT" update
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already on the latest"
}

@test "update: resolves its own path through a symlink" {
  # `command -v ataegina` must return a SYMLINK so ate_self_path walks the chain.
  local realdir="$ATE_TMP/real" linkdir="$ATE_TMP/linkbin"
  mkdir -p "$realdir" "$linkdir"
  cp "$ATE_SCRIPT" "$realdir/ataegina"; chmod +x "$realdir/ataegina"
  ln -s "$realdir/ataegina" "$linkdir/ataegina"
  feed_tag "v0.0.1"; serve_release "v0.0.1"
  run env PATH="$linkdir:$PATH" \
    ATE_RELEASES_URL="file://$STUB/latest.json" ATE_RAW_BASE="file://$STUB" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    bash "$ATE_SCRIPT" update
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already on the latest"
}

@test "update: a feed with no tag_name is treated as unreachable" {
  printf '{"name": "not a tag"}\n' > "$STUB/latest.json"
  run_update
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "could not reach the release feed"
}

# --- the throttled version-check notice (opt-in, runs at the end of `up`) -------

@test "version-check notice: a non-numeric throttle stamp is treated as never-checked" {
  local repo; repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='true'"
  cd "$repo"
  feed_tag "v99.0.0"
  mkdir -p "$ATE_TMP/registry"
  printf 'garbage-not-a-timestamp\n' > "$ATE_TMP/registry/.update-check"
  run env ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    ATE_UPDATE_CHECK=1 ATE_RELEASES_URL="file://$STUB/latest.json" \
    bash "$ATE_SCRIPT" up backend --scope backend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "a newer version is available (v99.0.0)"
}

@test "version-check notice: prints when a newer tag is published (opt-in)" {
  local repo; repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='true'"
  cd "$repo"
  feed_tag "v99.0.0"
  run env ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    ATE_UPDATE_CHECK=1 ATE_RELEASES_URL="file://$STUB/latest.json" \
    bash "$ATE_SCRIPT" up backend --scope backend
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "a newer version is available (v99.0.0)"
}

@test "version-check notice: throttled to once per 24h (stamp within window is skipped)" {
  local repo; repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='true'"
  cd "$repo"
  feed_tag "v99.0.0"
  mkdir -p "$ATE_TMP/registry"
  printf '%s\n' "$(date +%s)" > "$ATE_TMP/registry/.update-check"   # fresh stamp -> throttled
  run env ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    ATE_UPDATE_CHECK=1 ATE_RELEASES_URL="file://$STUB/latest.json" \
    bash "$ATE_SCRIPT" up backend --scope backend
  [ "$status" -eq 0 ]
  refute_output_has "a newer version is available"
}

@test "version-check notice: off by default (no ATE_UPDATE_CHECK)" {
  local repo; repo="$(make_repo "$ATE_TMP/repo")"
  write_config "$repo" "BACKEND_DIR='.'" "BACKEND_CMD='true'"
  cd "$repo"
  feed_tag "v99.0.0"
  run env ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    LOG_DIR_BASE="$ATE_TMP/logs/ate-wt" \
    ATE_RELEASES_URL="file://$STUB/latest.json" \
    bash "$ATE_SCRIPT" up backend --scope backend
  [ "$status" -eq 0 ]
  refute_output_has "a newer version is available"
}
