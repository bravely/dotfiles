#!/usr/bin/env bats
#
# Tests for run_after_claude-marketplaces.sh, which re-registers a declared Claude
# Code marketplace whose registration has drifted from its declared source, so its
# plugins keep loading. It runs straight from the repo, as chezmoi runs it, against
# the stubbed claude.

bats_require_minimum_version 1.5.0
load harness

run_script() { run in_sandbox sh "$REPO_ROOT/run_after_claude-marketplaces.sh"; }

# The declaration chezmoi writes: pstack from cursor-plugins, declared as the GitHub
# repo, plus a disabled plugin from the same marketplace.
declare_settings() {
  mkdir -p "$HOME/.claude"
  cat >"$HOME/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": {
    "pstack@cursor-plugins": true,
    "cursor-team-kit@cursor-plugins": false,
    "voicemode@voicemode": true
  },
  "extraKnownMarketplaces": {
    "cursor-plugins": {
      "source": { "source": "github", "repo": "cursor/plugins" },
      "autoUpdate": true
    },
    "voicemode": {
      "source": { "source": "github", "repo": "mbailey/voicemode" }
    }
  }
}
JSON
}

# register NAME SOURCE_JSON...: what known_marketplaces.json says each was added from.
register() {
  local entries='{}'
  while [ $# -gt 0 ]; do
    entries=$(jq --arg n "$1" --argjson s "$2" '.[$n] = {source: $s, installLocation: "/x"}' <<<"$entries")
    shift 2
  done
  mkdir -p "$HOME/.claude/plugins"
  printf '%s\n' "$entries" >"$HOME/.claude/plugins/known_marketplaces.json"
}

GITHUB_CURSOR='{"source":"github","repo":"cursor/plugins"}'
GIT_CURSOR='{"source":"git","url":"https://github.com/cursor/plugins.git"}'
GITHUB_VOICEMODE='{"source":"github","repo":"mbailey/voicemode"}'

@test "re-registers a marketplace added from a git URL its settings declare as a GitHub repo" {
  declare_settings
  register cursor-plugins "$GIT_CURSOR" voicemode "$GITHUB_VOICEMODE"
  run_script
  [ "$status" -eq 0 ]
  [ "$(stub claude calls)" = "plugin marketplace remove cursor-plugins
plugin marketplace add cursor/plugins
plugin install pstack@cursor-plugins" ]
}

@test "puts back the settings file chezmoi wrote after the CLI rewrites it" {
  declare_settings
  cat "$HOME/.claude/settings.json" >"$HOME/expected.json"
  register cursor-plugins "$GIT_CURSOR"
  run_script
  [ "$status" -eq 0 ]
  cmp "$HOME/expected.json" "$HOME/.claude/settings.json"
  [ ! -e "$HOME/.claude/settings.json.chezmoi-heal" ]
}

@test "re-registers from the URL when settings declare a git source" {
  declare_settings
  jq --argjson s "$GIT_CURSOR" '.extraKnownMarketplaces["cursor-plugins"].source = $s' \
    "$HOME/.claude/settings.json" >"$HOME/s.json"
  mv "$HOME/s.json" "$HOME/.claude/settings.json"
  register cursor-plugins "$GITHUB_CURSOR"
  run_script
  [ "$status" -eq 0 ]
  [ "$(stub claude calls | sed -n 2p)" = "plugin marketplace add https://github.com/cursor/plugins.git" ]
}

@test "leaves claude alone when every registration matches its declaration" {
  declare_settings
  register cursor-plugins "$GITHUB_CURSOR" voicemode "$GITHUB_VOICEMODE"
  run_script
  [ "$status" -eq 0 ]
  [ -z "$(stub claude calls)" ]
}

@test "leaves a declared marketplace that is not registered yet to Claude Code's first launch" {
  declare_settings
  register voicemode "$GITHUB_VOICEMODE"
  run_script
  [ "$status" -eq 0 ]
  [ -z "$(stub claude calls)" ]
}

@test "does nothing before Claude Code has registered any marketplace" {
  declare_settings
  run_script
  [ "$status" -eq 0 ]
  [ -z "$(stub claude calls)" ]
}

@test "does nothing before claude is installed, so a new machine's first apply passes" {
  declare_settings
  register cursor-plugins "$GIT_CURSOR"
  rm "$HOME/.local/bin/claude"
  hide claude
  run_script
  [ "$status" -eq 0 ]
  [ -z "$(stub claude calls)" ]
}

@test "fails the apply when re-adding fails, and still puts the settings file back" {
  declare_settings
  cat "$HOME/.claude/settings.json" >"$HOME/expected.json"
  register cursor-plugins "$GIT_CURSOR"
  stub claude fail 'plugin marketplace add' 1 'clone failed'
  run_script
  [ "$status" -eq 1 ]
  cmp "$HOME/expected.json" "$HOME/.claude/settings.json"
}
