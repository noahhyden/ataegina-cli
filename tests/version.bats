#!/usr/bin/env bats
# Version comparator + --version / --help smoke.
#
# The comparator (ate_version_gt) is internal, so we exercise it through the
# `update` path: with the release feed pointed at a local file:// stub, `update`
# compares the published tag against the script's own VERSION. A tag <= VERSION
# yields "already on the latest version" (the comparator said "not greater");
# a tag > VERSION drives a real (stubbed, local) self-replace. No network.

load helper

setup() {
  common_setup
  CUR="$(sed -n 's/^VERSION="\{0,1\}\([0-9][^"]*\)"\{0,1\}.*/\1/p' "$ATE_SCRIPT" | head -n1)"
}
teardown() { common_teardown; }

# Run `update` with the feed + raw base pointed at a local stub dir. $1 is the
# tag the feed advertises. The stub serves <RAW_BASE>/<tag>/ataegina too.
run_update_with_tag() {
  local tag="$1"
  local stub="$ATE_TMP/stub"
  mkdir -p "$stub/$tag"
  printf '{"tag_name": "%s"}\n' "$tag" > "$stub/latest.json"
  # The "release" script is just a copy of the current one (so a same-or-newer
  # self-replace, if it happens, installs something that still parses).
  cp "$ATE_SCRIPT" "$stub/$tag/ataegina"
  if command -v shasum >/dev/null 2>&1; then
    ( cd "$stub/$tag" && shasum -a 256 ataegina > ataegina.sha256 )
  fi
  # Install into a writable copy so a real replace does not touch the source.
  local installed="$ATE_TMP/bin/ataegina"
  mkdir -p "$ATE_TMP/bin"
  cp "$ATE_SCRIPT" "$installed"
  chmod +x "$installed"
  run env \
    ATE_RELEASES_URL="file://$stub/latest.json" \
    ATE_RAW_BASE="file://$stub" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    bash "$installed" update
}

@test "--version prints the version line" {
  run ate --version
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE "^ataegina [0-9]+\.[0-9]+\.[0-9]+"
  echo "$output" | grep -q "$CUR"
}

@test "--help prints usage and the command list" {
  run ate --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "usage:"
  echo "$output" | grep -q "ataegina up"
  echo "$output" | grep -q "ataegina db"
}

@test "comparator: an OLDER published tag is not greater (already on latest)" {
  run_update_with_tag "v0.0.1"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already on the latest version"
}

@test "comparator: the SAME version is not greater (already on latest)" {
  run_update_with_tag "v$CUR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already on the latest version"
}

@test "comparator: a NEWER published tag is greater (drives an update)" {
  # Bump only the patch component so it is unambiguously greater than CUR.
  run_update_with_tag "v99.0.0"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE "updated .* -> v99\.0\.0"
}
