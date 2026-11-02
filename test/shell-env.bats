#!/usr/bin/env bats
#
# Tests for private_dot_claude/shell-env.sh, which non-interactive bash reads through
# $BASH_ENV so tool-spawned shells can find mise-managed tools.

bats_require_minimum_version 1.5.0
load harness

# path_after_sourcing SHELL [PATH]: $PATH after sourcing the file in a fresh SHELL.
path_after_sourcing() {
  in_sandbox ${2+PATH="$2"} "$1" -c '. "$HOME/.claude/shell-env.sh"; printf %s "$PATH"'
}

@test "puts the mise shims first on PATH" {
  run path_after_sourcing sh
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.local/share/mise/shims:$SANDBOX_PATH" ]
}

@test "works the same under bash 3.2 as under sh" {
  run path_after_sourcing bash
  [ "$output" = "$HOME/.local/share/mise/shims:$SANDBOX_PATH" ]
}

@test "does not add the shims twice when sourced again" {
  run in_sandbox sh -c '. "$HOME/.claude/shell-env.sh"; . "$HOME/.claude/shell-env.sh"; printf %s "$PATH"'
  [ "$output" = "$HOME/.local/share/mise/shims:$SANDBOX_PATH" ]
}

@test "leaves PATH alone when the shims are already on it, wherever they are" {
  already="$SANDBOX_PATH:$HOME/.local/share/mise/shims"
  run path_after_sourcing sh "$already"
  [ "$output" = "$already" ]
}

@test "a non-interactive bash finds a mise tool through BASH_ENV" {
  mkdir -p "$HOME/.local/share/mise/shims"
  printf '#!/bin/sh\necho mix from the shim\n' >"$HOME/.local/share/mise/shims/mix"
  chmod +x "$HOME/.local/share/mise/shims/mix"
  run in_sandbox BASH_ENV="$HOME/.claude/shell-env.sh" bash -c 'mix'
  [ "$status" -eq 0 ]
  [ "$output" = "mix from the shim" ]
  # the same shell without BASH_ENV cannot see it, so the pass above means something
  run -127 in_sandbox bash -c 'mix'
}
