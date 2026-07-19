#!/usr/bin/env bats
# config set / get / unset / list round-trips and guard rails.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
}
teardown() { common_teardown; }

@test "set then get round-trips a value with a literal \$VAR and single quotes" {
  cd "$REPO"
  val='npx next dev -p $FRONTEND_PORT # don'\''t expand $VAR'
  run ate config set FRONTEND_CMD "$val"
  [ "$status" -eq 0 ]

  run ate config get FRONTEND_CMD
  [ "$status" -eq 0 ]
  [ "$output" = "$val" ]

  # The stored line keeps $FRONTEND_PORT and $VAR literal (single-quoted), so
  # they never expand when the config is sourced. Assert the dollar references
  # survive verbatim in the file.
  grep -qF '$FRONTEND_PORT' "$REPO/ataegina.config.sh"
  grep -qF '$VAR' "$REPO/ataegina.config.sh"
}

@test "set replaces an existing assignment in place, not append a duplicate" {
  cd "$REPO"
  ate config set BACK_PORT_BASE 8000
  ate config set BACK_PORT_BASE 9000
  run ate config get BACK_PORT_BASE
  [ "$output" = "9000" ]
  n="$(grep -c '^BACK_PORT_BASE=' "$REPO/ataegina.config.sh")"
  [ "$n" -eq 1 ]
}

@test "set rejects a non-whitelisted key (nonzero, nothing written)" {
  cd "$REPO"
  run ate config set EVIL_KEY 'rm -rf /'
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "unknown key"
  # If a config file got created, it must not contain the bogus key.
  if [ -f "$REPO/ataegina.config.sh" ]; then
    refute grep -q "EVIL_KEY" "$REPO/ataegina.config.sh"
  fi
}

@test "set rejects a hook function name with a targeted hint" {
  cd "$REPO"
  run ate config set ate_start_backend 'true'
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "hook"
}

@test "unset removes the assignment" {
  cd "$REPO"
  ate config set DB_NAME myapp
  run ate config get DB_NAME
  [ "$output" = "myapp" ]
  ate config unset DB_NAME
  run ate config get DB_NAME
  [ -z "$output" ]
  refute grep -q '^DB_NAME=' "$REPO/ataegina.config.sh"
}

@test "set preserves comments and hook functions already in the file" {
  cd "$REPO"
  cat > "$REPO/ataegina.config.sh" <<'EOF'
# my hand-written config header
FRONT_PORT_BASE=5173

# a custom start hook the CLI must never clobber
ate_start_backend() {
  echo "custom: $BACKEND_PORT"
}
# trailing comment
EOF
  ate config set BACK_PORT_BASE 8100
  # The hook, both comments, and the untouched key all survive.
  grep -q "my hand-written config header" "$REPO/ataegina.config.sh"
  grep -q "a custom start hook" "$REPO/ataegina.config.sh"
  grep -q "trailing comment" "$REPO/ataegina.config.sh"
  grep -q 'ate_start_backend() {' "$REPO/ataegina.config.sh"
  grep -q 'echo "custom: \$BACKEND_PORT"' "$REPO/ataegina.config.sh"
  grep -q '^FRONT_PORT_BASE=5173' "$REPO/ataegina.config.sh"
  # The CLI stores values single-quoted, so the appended assignment is 8100 quoted.
  grep -qE "^BACK_PORT_BASE='?8100'?" "$REPO/ataegina.config.sh"
  # And it round-trips through get.
  run ate config get BACK_PORT_BASE
  [ "$output" = "8100" ]
}

@test "list shows keys, effective values, and the loaded config path" {
  cd "$REPO"
  ate config set DB_NAME myapp
  run ate config list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "DB_NAME"
  echo "$output" | grep -q "myapp"
  echo "$output" | grep -q "set in"
}

@test "get/unset also reject unknown keys" {
  cd "$REPO"
  run ate config get NOPE
  [ "$status" -ne 0 ]
  run ate config unset NOPE
  [ "$status" -ne 0 ]
}

@test "path prints the config file get/set operate on" {
  cd "$REPO"
  run ate config path
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ataegina.config.sh"
}

# --- --global target + argument validation + unset edge branches ---------------

# The --global target is $REGISTRY_DIR/ataegina.config.sh (the machine-local config).

@test "config path --global prints the global (registry-dir) config path" {
  cd "$REPO"
  run ate config path --global
  [ "$status" -eq 0 ]
  [ "$output" = "$ATE_TMP/registry/ataegina.config.sh" ]
}

@test "config set --global writes into the global config file" {
  cd "$REPO"
  run ate config set --global BACK_PORT_BASE 7777
  [ "$status" -eq 0 ]
  grep -q '^BACK_PORT_BASE=' "$ATE_TMP/registry/ataegina.config.sh"
}

@test "config get with no KEY errors" {
  cd "$REPO"; run ate config get
  [ "$status" -eq 2 ]; echo "$output" | grep -qi "missing KEY"
}

@test "config set with no VALUE errors" {
  cd "$REPO"; run ate config set BACK_PORT_BASE
  [ "$status" -eq 2 ]; echo "$output" | grep -qi "missing VALUE"
}

@test "config unset with no KEY errors" {
  cd "$REPO"; run ate config unset
  [ "$status" -eq 2 ]; echo "$output" | grep -qi "missing KEY"
}

@test "config with an unknown subcommand errors" {
  cd "$REPO"; run ate config frobnicate
  [ "$status" -eq 2 ]; echo "$output" | grep -qi "unknown subcommand"
}

@test "config with too many arguments errors" {
  cd "$REPO"; run ate config set A B C
  [ "$status" -eq 2 ]; echo "$output" | grep -qi "too many arguments"
}

@test "config unset a key that is not in the file notes nothing removed" {
  cd "$REPO"
  ate config set BACK_PORT_BASE 8000
  run ate config unset FRONT_PORT_BASE     # a known key, but not present in the file
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "nothing removed"
}

@test "config unset when no config file exists errors" {
  cd "$REPO"                                 # make_repo leaves no config file
  run ate config unset BACK_PORT_BASE
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "no config file"
}
