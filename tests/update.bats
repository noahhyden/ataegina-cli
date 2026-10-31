#!/usr/bin/env bats
# `ataegina update` delegates to install.sh. Driven locally: a stub install.sh is
# served under a file:// ATE_RAW_BASE at HEAD/install.sh, and a writable copy of the
# script sits on PATH as `ataegina` so ate_self_path targets the copy.

load helper

setup() {
  common_setup
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || skip "need curl or wget for file:// fetch"
  STUB="$ATE_TMP/stub"
  BIN="$ATE_TMP/bin"
  mkdir -p "$STUB/HEAD" "$BIN"
  cp "$ATE_SCRIPT" "$BIN/ataegina"; chmod +x "$BIN/ataegina"
}
teardown() { common_teardown; }

run_update() {
  run env PATH="$BIN:$PATH" \
    ATE_RELEASES_URL="file://$STUB/latest.json" \
    ATE_RAW_BASE="file://$STUB" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    bash "$ATE_SCRIPT" update
}

@test "update: runs the fetched install.sh with ATE_BIN set to the install dir" {
  cat > "$STUB/HEAD/install.sh" <<SH
#!/bin/sh
echo "bin=\$ATE_BIN raw=\$ATE_RAW_BASE rel=\$ATE_RELEASES_URL"
SH
  run_update
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "bin=$BIN "
  echo "$output" | grep -q "raw=file://$STUB "
  echo "$output" | grep -q "rel=file://$STUB/latest.json"
}

@test "update: install.sh failure propagates its exit status" {
  printf '#!/bin/sh\nexit 7\n' > "$STUB/HEAD/install.sh"
  run_update
  [ "$status" -eq 7 ]
}

@test "update: an empty install.sh aborts" {
  : > "$STUB/HEAD/install.sh"
  run_update
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "could not fetch install.sh"
}

@test "update: a missing install.sh aborts" {
  run_update
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "could not fetch install.sh"
}

@test "update: a non-writable install target aborts before fetching" {
  printf '#!/bin/sh\necho RAN\n' > "$STUB/HEAD/install.sh"
  chmod -w "$BIN/ataegina"
  run_update
  chmod +w "$BIN/ataegina"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not writable"
  refute_output_has "RAN"
}

@test "update: resolves its own path through a symlink" {
  local realdir="$ATE_TMP/real" linkdir="$ATE_TMP/linkbin"
  mkdir -p "$realdir" "$linkdir"
  cp "$ATE_SCRIPT" "$realdir/ataegina"; chmod +x "$realdir/ataegina"
  ln -s "$realdir/ataegina" "$linkdir/ataegina"
  printf '#!/bin/sh\necho "bin=$ATE_BIN"\n' > "$STUB/HEAD/install.sh"
  run env PATH="$linkdir:$PATH" ATE_RAW_BASE="file://$STUB" \
    ATE_REGISTRY_DIR="$ATE_TMP/registry" ATE_PORT_TOOL=none \
    bash "$ATE_SCRIPT" update
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "bin=$realdir"
}
