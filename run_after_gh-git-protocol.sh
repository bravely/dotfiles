#!/bin/sh
#
# Keep gh on SSH, so the remotes `gh repo clone` and `gh repo fork` write are
# SSH. gh owns ~/.config/gh/config.yml and rewrites it, so this sets the one key
# instead of chezmoi managing the whole file. Runs on every apply: on a new
# machine gh arrives with `brew bundle`, after the first apply, so until then
# this does nothing.

set -eu

command -v gh >/dev/null 2>&1 || exit 0
[ "$(gh config get git_protocol)" = ssh ] || gh config set git_protocol ssh
