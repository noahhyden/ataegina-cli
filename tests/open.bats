#!/usr/bin/env bats
# `ataegina open [frontend|backend]` — open this worktree's derived URL in a
# browser. Opener resolution: $BROWSER (scriptable), else xdg-open, else open.
#
# Spec: default target is the frontend (the thing you look at); `backend` opens
# the backend URL. The URL is this tree's derived one (base port + index). An
# unknown target is an error (exit 2); with no opener available it prints the URL
# so you can open it yourself.
#
# Hermetic: $BROWSER (or a fake xdg-open on PATH) points at a stub that records
# the URL it was handed — no real browser is launched. ATE_PORT_TOOL=none.

load helper

setup() {
  common_setup
  REPO="$(make_repo "$ATE_TMP/repo")"
  # A stub "browser" that records the URL it is given, then exits 0.
  OPENER="$ATE_TMP/opener.sh"
  MARK="$ATE_TMP/opened.url"
  printf '#!/bin/sh\nprintf "%%s" "$1" > "%s"\n' "$MARK" > "$OPENER"
  chmod +x "$OPENER"
}
teardown() { common_teardown; }

@test "open (default) hands the frontend URL to \$BROWSER" {
  cd "$REPO"
  BROWSER="$OPENER" run ate open
  [ "$status" -eq 0 ]
  [ "$(cat "$MARK")" = "http://localhost:5173" ]
}

@test "open frontend hands the frontend URL to \$BROWSER" {
  cd "$REPO"
  BROWSER="$OPENER" run ate open frontend
  [ "$status" -eq 0 ]
  [ "$(cat "$MARK")" = "http://localhost:5173" ]
}

@test "open backend hands the backend URL to \$BROWSER" {
  cd "$REPO"
  BROWSER="$OPENER" run ate open backend
  [ "$status" -eq 0 ]
  [ "$(cat "$MARK")" = "http://localhost:8000" ]
}

@test "open uses a linked worktree's own derived port" {
  wt="$(add_worktree "$REPO" wtA)"
  cd "$wt"
  BROWSER="$OPENER" run ate open frontend
  [ "$status" -eq 0 ]
  [ "$(cat "$MARK")" = "http://localhost:5174" ]
}

@test "open falls back to xdg-open when \$BROWSER is unset" {
  # Fake xdg-open on PATH; it records the URL like the stub above.
  local bin="$ATE_TMP/bin"; mkdir -p "$bin"
  printf '#!/bin/sh\nprintf "%%s" "$1" > "%s"\n' "$MARK" > "$bin/xdg-open"
  chmod +x "$bin/xdg-open"
  cd "$REPO"
  BROWSER="" PATH="$bin:$PATH" run ate open frontend
  [ "$status" -eq 0 ]
  [ "$(cat "$MARK")" = "http://localhost:5173" ]
}

@test "open with an unknown target errors (exit 2)" {
  cd "$REPO"
  BROWSER="$OPENER" run ate open sideways
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "unknown target"
}

@test "open passes a \$BROWSER that carries its own arguments" {
  cd "$REPO"
  # $BROWSER may be a command with flags; it must word-split, not be one argv0.
  local logf="$ATE_TMP/args.log"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s"\n' "$logf" > "$ATE_TMP/br.sh"
  chmod +x "$ATE_TMP/br.sh"
  BROWSER="$ATE_TMP/br.sh --new-window" run ate open frontend
  [ "$status" -eq 0 ]
  grep -qx -- "--new-window" "$logf"
  grep -qx "http://localhost:5173" "$logf"
}

@test "open outside a git worktree errors clearly" {
  cd "$ATE_TMP"
  BROWSER="$OPENER" run ate open
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not inside a git worktree"
}
