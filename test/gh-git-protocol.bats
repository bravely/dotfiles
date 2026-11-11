#!/usr/bin/env bats
#
# Tests for run_after_gh-git-protocol.sh, which keeps gh's git_protocol on SSH on
# every chezmoi apply. It runs straight from the repo, as chezmoi runs it, against
# the stubbed gh.

bats_require_minimum_version 1.5.0
load harness

run_script() { run in_sandbox sh "$REPO_ROOT/run_after_gh-git-protocol.sh"; }

@test "switches gh from its https default to ssh" {
  run_script
  [ "$status" -eq 0 ]
  [ "$(stub gh calls)" = "config get git_protocol
config set git_protocol ssh" ]
}

@test "leaves gh alone when it is already on ssh" {
  stub gh protocol ssh
  run_script
  [ "$status" -eq 0 ]
  [ "$(stub gh calls)" = "config get git_protocol" ]
}

@test "does nothing before gh is installed, so a new machine's first apply passes" {
  hide gh
  run_script
  [ "$status" -eq 0 ]
  [ -z "$(stub gh calls)" ]
}

@test "fails when gh cannot save the setting, so the apply fails" {
  stub gh fail 'config set' 1 'failed to write config'
  run_script
  [ "$status" -eq 1 ]
}
