#!/usr/bin/env bats
# --version / --help smoke. The version comparator and the full `update` flow are
# covered source-attributed in update.bats (this file kept lean to avoid running
# the self-replace twice).

load helper

setup() {
  common_setup
  CUR="$(sed -n 's/^VERSION="\{0,1\}\([0-9][^"]*\)"\{0,1\}.*/\1/p' "$ATE_SCRIPT" | head -n1)"
}
teardown() { common_teardown; }

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

@test "no args prints usage and exits 0" {
  run ate
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "usage:"
}

@test "an unknown command prints usage guidance and exits nonzero" {
  run ate no-such-command
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE "usage:|unknown"
}

@test "down with an unknown mode errors" {
  local repo; repo="$(make_repo "$ATE_TMP/repo")"
  cd "$repo"
  run ate down bogusmode
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "unknown argument"
}
