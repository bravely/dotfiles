#!/bin/sh
#
# Give Claude Code the Todoist CLI's own skill, so a session knows td's commands.
# td writes it to ~/.claude/skills/todoist-cli/SKILL.md and rewrites it itself
# after each upgrade, so this only installs it when it is missing. Runs on every
# apply: on a new machine td arrives with `brew bundle`, after the first apply,
# so until then this does nothing.

set -eu

command -v td >/dev/null 2>&1 || exit 0
[ -e "$HOME/.claude/skills/todoist-cli/SKILL.md" ] || td skill install claude-code
