#!/usr/bin/env bats
#
# Tests for private_dot_claude/private_executable_statusline.sh, which Claude Code
# runs to draw its status line: a Starship prompt plus the model and context use,
# from the session JSON on stdin. It is bash 3.2 (macOS's), jq is real, and
# starship is a stub that prints a canned prompt the way the real one does.
#

load harness

# session MODEL PCT [DIR]: the JSON Claude Code sends. PCT is a number or null.
session() {
  jq -nc --arg model "$1" --argjson pct "$2" --arg dir "${3-}" '
    {model: {display_name: $model}, context_window: {used_percentage: $pct}}
    + (if $dir != "" then {workspace: {current_dir: $dir}} else {} end)'
}

# prompt: stdin is what `starship prompt` prints.
prompt() { stub starship prompt; }

# Starship's default format: a blank line, the segments, then the character line.
setup() {
  sandbox_init
  printf '\n~/dev/dotfiles on  main\n❯ \n' | prompt
}

@test "shows the prompt, the model and the context used, separated by dots" {
  run statusline <<<"$(session Opus 42.7)"
  [ "$status" -eq 0 ]
  [ "$output" = "~/dev/dotfiles on  main  ·  Opus · 42% ctx" ]
}

@test "the context figure is whole percent, rounded down" {
  run statusline <<<"$(session Opus 99.9)"
  [[ $output == *"Opus · 99% ctx" ]] || false
}

@test "before the first response the percentage is null and only the model is shown" {
  run statusline <<<"$(session Opus null)"
  [ "$output" = "~/dev/dotfiles on  main  ·  Opus" ]
}

@test "with no model it still shows the context used" {
  run statusline <<<'{"context_window": {"used_percentage": 12}}'
  [ "$output" = "~/dev/dotfiles on  main  ·  12% ctx" ]
}

@test "keeps only starship's first non-blank line, dropping the blank line and the character line" {
  run statusline <<<"$(session Opus 1)"
  [[ $output != *"❯"* ]] || false
  [ "$(wc -l <<<"$output" | tr -d ' ')" -eq 1 ]
}

@test "asks starship for plain output, not zsh's %{ %} escapes" {
  run statusline <<<"$(session Opus 1)"
  [[ $output != *"%{"* ]] || false
}

@test "renders the prompt for the session's directory, not the one the script was started in" {
  mkdir -p "$HOME/proj"
  printf '@PWD@\n' | prompt
  run statusline <<<"$(session Opus 1 "$HOME/proj")"
  [ "$output" = "$HOME/proj  ·  Opus · 1% ctx" ]
}

@test "falls back to the session's cwd when there is no workspace" {
  mkdir -p "$HOME/proj"
  printf '@PWD@\n' | prompt
  run statusline <<<"{\"cwd\": \"$HOME/proj\", \"model\": {\"display_name\": \"Opus\"}}"
  [ "$output" = "$HOME/proj  ·  Opus" ]
}

@test "a session directory that is gone does not stop the line being drawn" {
  printf '@PWD@\n' | prompt
  cd "$HOME"
  run statusline <<<"$(session Opus 1 "$HOME/deleted")"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME  ·  Opus · 1% ctx" ]
}

@test "without starship the model and context are still shown" {
  hide starship
  run statusline <<<"$(session Opus 42.7)"
  [ "$status" -eq 0 ]
  [ "$output" = "Opus · 42% ctx" ]
}

@test "with nothing to show it prints an empty line and exits 0" {
  hide starship
  run statusline <<<'{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "input that is not JSON does not make it fail" {
  run statusline <<<'not json'
  [ "$status" -eq 0 ]
}
