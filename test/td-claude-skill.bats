#!/usr/bin/env bats
#
# Tests for run_after_td-claude-skill.sh, which installs the Todoist CLI's own
# Claude Code skill on a chezmoi apply when it is missing. It runs straight from
# the repo, as chezmoi runs it, against the stubbed td.

bats_require_minimum_version 1.5.0
load harness

run_script() { run in_sandbox sh "$REPO_ROOT/run_after_td-claude-skill.sh"; }

skill=.claude/skills/todoist-cli/SKILL.md

@test "installs the skill when Claude Code does not have it" {
  run_script
  [ "$status" -eq 0 ]
  [ "$(stub td calls)" = "skill install claude-code" ]
  [ -f "$HOME/$skill" ]
}

@test "leaves an installed skill alone, since td refreshes it itself" {
  mkdir -p "$HOME/${skill%/*}"
  echo 'an earlier version' >"$HOME/$skill"
  run_script
  [ "$status" -eq 0 ]
  [ -z "$(stub td calls)" ]
  [ "$(cat "$HOME/$skill")" = 'an earlier version' ]
}

@test "does nothing before td is installed, so a new machine's first apply passes" {
  hide td
  run_script
  [ "$status" -eq 0 ]
  [ -z "$(stub td calls)" ]
  [ ! -e "$HOME/$skill" ]
}

@test "fails when td cannot install the skill, so the apply fails" {
  stub td fail 'skill install' 1 'EACCES: permission denied'
  run_script
  [ "$status" -eq 1 ]
}
