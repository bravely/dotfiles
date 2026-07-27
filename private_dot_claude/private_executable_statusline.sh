#!/usr/bin/env bash
# Claude Code status line: the real Starship prompt, plus session info Starship
# can't know about. Reads session JSON on stdin.
# Docs: https://code.claude.com/docs/en/statusline
set -uo pipefail

input=$(cat)
field() { jq -r "$1 // empty" <<<"$input"; }

# Starship renders for the process's cwd, which isn't necessarily the session's.
dir=$(field '.workspace.current_dir // .cwd')
[ -n "$dir" ] && cd "$dir" 2>/dev/null

# Two fixes for embedding starship here:
#  - STARSHIP_SHELL=sh, else it wraps colors in zsh's %{ %} escapes, which
#    Claude Code prints literally.
#  - The default `$all` format ends with $line_break$character, so the output is
#    blank line / segments / "❯". Keep only the first non-blank line.
prompt=$(STARSHIP_SHELL=sh starship prompt 2>/dev/null \
  | grep -v '^[[:space:]]*$' \
  | head -1 \
  | sed 's/[[:space:]]*$//')

model=$(field '.model.display_name')
pct=$(field '.context_window.used_percentage')

right="$model"
# Null until the first API response of a session, and again right after /compact.
[ -n "$pct" ] && right="${right:+$right · }${pct%.*}% ctx"

if [ -n "$prompt" ] && [ -n "$right" ]; then
  printf '%s  ·  %s\n' "$prompt" "$right"
else
  printf '%s%s\n' "$prompt" "$right"
fi
