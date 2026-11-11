#!/bin/sh
#
# Keep each declared Claude Code marketplace registered from the source
# settings.json declares. Runs on every apply.
#
# Claude Code keeps two records of a marketplace: the declaration in
# ~/.claude/settings.json (extraKnownMarketplaces, which chezmoi writes) and the
# registration in ~/.claude/plugins/known_marketplaces.json (which the CLI owns).
# When their sources differ, even as two spellings of one repo such as
# {"source":"github","repo":"cursor/plugins"} and
# {"source":"git","url":"https://github.com/cursor/plugins.git"}, Claude Code
# ignores the marketplace and every plugin from it stops loading. So for each
# declared marketplace whose registration has drifted, this re-registers it from
# the declared source and reinstalls the enabled plugins it lost.
#
# The CLI rewrites settings.json as it goes (reordering keys, dropping
# autoUpdate), so the file chezmoi just wrote is put back afterwards.
#
# A marketplace not registered yet is left alone: Claude Code registers declared
# ones itself on its first launch, from the declared source.

set -eu

settings=$HOME/.claude/settings.json
known=$HOME/.claude/plugins/known_marketplaces.json

command -v claude >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[ -f "$settings" ] && [ -f "$known" ] || exit 0

drifted=$(jq -r --slurpfile known "$known" '
  (.extraKnownMarketplaces // {}) | to_entries[]
  | select($known[0][.key] != null and $known[0][.key].source != .value.source)
  | .key' "$settings")
[ -n "$drifted" ] || exit 0

backup=$settings.chezmoi-heal
cat "$settings" >"$backup"
trap 'cat "$backup" >"$settings"; rm -f "$backup"' EXIT

for name in $drifted; do
  source=$(jq -r --arg name "$name" '
    .extraKnownMarketplaces[$name].source
    | if .source == "github" then .repo
      elif .source == "git" or .source == "url" then .url
      else empty end' "$settings")
  if [ -z "$source" ]; then
    echo "claude-marketplaces: $name is registered from a different source than settings.json declares, and its declared source type has no CLI form; fix it with /plugin" >&2
    continue
  fi
  plugins=$(jq -r --arg name "$name" '
    (.enabledPlugins // {}) | to_entries[]
    | select(.value == true and (.key | endswith("@" + $name))) | .key' "$settings")

  echo "claude-marketplaces: re-registering $name from $source" >&2
  claude plugin marketplace remove "$name"
  claude plugin marketplace add "$source"
  for plugin in $plugins; do
    claude plugin install "$plugin"
  done
done
