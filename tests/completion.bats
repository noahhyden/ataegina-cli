#!/usr/bin/env bats
# `ataegina completion <bash|zsh>` — print a shell completion script to stdout.
#
# Spec: prints a self-contained completion script for the requested shell that
# completes ataegina's subcommands (and one level of common arguments). It needs
# no git worktree — you source it from a shell rc file anywhere — so it must work
# outside a repo. An unknown or missing shell name is an error (exit 2).
#
# Hermetic: pure stdout, no registry/config/network. We validate the emitted
# script's syntax with `bash -n` / `zsh -n` and assert it lists the subcommands.

load helper

setup()    { common_setup; }
teardown() { common_teardown; }

# Every top-level subcommand should be offered by completion. Kept in sync with
# the dispatch; a missing one is a real gap this asserts against.
ALL_CMDS="init up down restart logs db ports env exec list move prune doctor config update completion"

@test "completion bash prints a sourceable bash script" {
  run ate completion bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "complete -F"
  # Valid bash.
  printf '%s\n' "$output" > "$ATE_TMP/comp.bash"
  bash -n "$ATE_TMP/comp.bash"
}

# Functional: source the emitted script and drive the completion function, so we
# assert on what it ACTUALLY completes — not just substrings that could appear
# elsewhere in the script (e.g. a subcommand named in an argument `case` arm).
@test "completion bash actually completes every subcommand at the top level" {
  run ate completion bash
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$ATE_TMP/comp.bash"
  source "$ATE_TMP/comp.bash"
  COMP_WORDS=(ataegina ""); COMP_CWORD=1
  _ataegina
  local reply=" ${COMPREPLY[*]} "
  for c in $ALL_CMDS; do
    case "$reply" in
      *" $c "*) : ;;
      *) echo "top-level completion did not offer: $c (got:$reply)"; return 1 ;;
    esac
  done
}

@test "completion bash completes mode words + flags after up" {
  run ate completion bash
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$ATE_TMP/comp.bash"
  source "$ATE_TMP/comp.bash"
  COMP_WORDS=(ataegina up ""); COMP_CWORD=2
  _ataegina
  local reply=" ${COMPREPLY[*]} "
  case "$reply" in *" backend "*) : ;; *) echo "no 'backend' after up (got:$reply)"; return 1 ;; esac
  case "$reply" in *" --scope "*) : ;; *) echo "no '--scope' after up (got:$reply)"; return 1 ;; esac
}

@test "completion bash completes db subcommands" {
  run ate completion bash
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$ATE_TMP/comp.bash"
  source "$ATE_TMP/comp.bash"
  COMP_WORDS=(ataegina db ""); COMP_CWORD=2
  _ataegina
  local reply=" ${COMPREPLY[*]} "
  for w in name url create drop; do
    case "$reply" in *" $w "*) : ;; *) echo "db did not complete '$w' (got:$reply)"; return 1 ;; esac
  done
}

@test "completion zsh prints a #compdef script" {
  run ate completion zsh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "#compdef"
  echo "$output" | grep -qw "restart"
  # Valid zsh, when zsh is available.
  if command -v zsh >/dev/null 2>&1; then
    printf '%s\n' "$output" > "$ATE_TMP/comp.zsh"
    zsh -n "$ATE_TMP/comp.zsh"
  fi
}

@test "completion works outside a git worktree (no repo needed)" {
  cd "$ATE_TMP"                      # not a git repo
  run ate completion bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "complete -F"
}

@test "completion with no shell argument errors (exit 2)" {
  run ate completion
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "bash|zsh"
}

@test "completion with an unknown shell errors (exit 2)" {
  run ate completion fish
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "unknown shell"
}
