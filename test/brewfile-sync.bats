#!/usr/bin/env bats
#
# Tests for dot_local/bin/executable_brewfile-sync, which compares `brew bundle
# dump` with the Brewfile lists in the chezmoi source. brew is a stub that prints
# whatever dump the test gives it; chezmoi is the real one, reading a fixture source
# of three small lists from the sandbox's config, so the script's questions to
# chezmoi (where is the source, what machine type is this) are answered for real.
#

bats_require_minimum_version 1.5.0
load harness

# lists COMMON PERSONAL WORK: a chezmoi source with just those three lists, used for
# the work machine unless a test says otherwise.
lists() {
  SRC=$SANDBOX/source
  mkdir -p "$SRC/.chezmoitemplates"
  printf '%s\n' "$1" >"$SRC/.chezmoitemplates/Brewfile.common"
  printf '%s\n' "$2" >"$SRC/.chezmoitemplates/Brewfile.personal"
  printf '%s\n' "$3" >"$SRC/.chezmoitemplates/Brewfile.work"
  chezmoi_config source="$SRC" machineType="${MACHINE:-work}"
}

# installed: stdin is what `brew bundle dump` prints.
installed() { stub brew dump; }

@test "-h prints usage and exits 0" {
  run brewfile-sync -h
  [ "$status" -eq 0 ]
  [[ $output == "Usage: brewfile-sync"* ]] || false
}

@test "any argument but -h exits 2 with usage on stderr" {
  run --separate-stderr brewfile-sync now
  [ "$status" -eq 2 ]
  [[ $stderr == "Usage: brewfile-sync"* ]] || false
}

@test "refuses when brew is not installed" {
  lists 'brew "jq"' '' ''
  hide brew
  run brewfile-sync
  [ "$status" -eq 1 ]
  [[ $output == *"brew not found"* ]] || false
}

@test "refuses when chezmoi is not installed" {
  hide chezmoi
  run brewfile-sync
  [ "$status" -eq 1 ]
  [[ $output == *"chezmoi not found"* ]] || false
}

@test "refuses when the source does not hold all three lists" {
  lists 'brew "jq"' '' ''
  rm "$SRC/.chezmoitemplates/Brewfile.personal"
  run brewfile-sync
  [ "$status" -eq 1 ]
  [[ $output == *"lists not found in $HOME/.local/share/chezmoi/.chezmoitemplates"* ]] || false
}

@test "it names the machine type chezmoi has and the lists it read" {
  lists '' '' ''
  installed <<<''
  run brewfile-sync
  [ "$status" -eq 0 ]
  expected="Machine type: work
Lists: $HOME/.local/share/chezmoi/.chezmoitemplates"
  [[ $output == "$expected"* ]] || false
}

@test "New: an installed formula in no list is shown with its comment, ready to paste" {
  lists 'brew "jq"' '' ''
  installed <<'DUMP'
# Line-oriented search tool
brew "ripgrep"
brew "jq"
DUMP
  run brewfile-sync
  [ "$status" -eq 0 ]
  expected='New -- installed but in no list (1):

# Line-oriented search tool
brew "ripgrep"'
  [[ $output == *"$expected"* ]] || false
  [[ $output != *'brew "jq"'* ]] || false
}

@test "New: none when everything installed is in some list, including the other machine type's" {
  lists 'brew "jq"' 'cask "steam"' 'cask "slack"'
  installed <<'DUMP'
brew "jq"
cask "steam"
DUMP
  run brewfile-sync
  [[ $output == *"New: none"* ]] || false
}

@test "New: lists the new entries in sorted order" {
  lists '' '' ''
  installed <<'DUMP'
brew "zoxide"
brew "atuin"
brew "fzf"
DUMP
  run brewfile-sync
  [[ $output == *'brew "atuin"'*'brew "fzf"'*'brew "zoxide"'* ]] || false
  [[ $output == *"(3):"* ]] || false
}

@test "New: changing an entry's options does not make it new" {
  lists 'brew "mysql", restart_service: true' '' ''
  installed <<<'brew "mysql", restart_service: :changed'
  run brewfile-sync
  [[ $output == *"New: none"* ]] || false
}

@test "New: a tap is left out when a listed entry names it in full" {
  lists 'brew "owner/tap/tool"' '' ''
  installed <<'DUMP'
tap "owner/tap"
brew "owner/tap/tool"
DUMP
  run brewfile-sync
  [[ $output == *"New: none"* ]] || false
}

@test "New: a tap no listed entry names is shown" {
  lists 'brew "jq"' '' ''
  installed <<'DUMP'
tap "owner/other"
brew "jq"
DUMP
  run brewfile-sync
  [[ $output == *'tap "owner/other"'* ]] || false
}

@test "Missing: an entry in common or this machine's list that is not installed" {
  lists 'brew "jq"' 'cask "steam"' 'cask "slack"'
  installed <<<''
  run brewfile-sync
  [[ $output == *"Missing -- listed for this machine but not installed (2):"* ]] || false
  [[ $output == *'  brew "jq"'* ]] || false
  [[ $output == *'  cask "slack"'* ]] || false
}

@test "Missing: the other machine type's list is ignored" {
  lists 'brew "jq"' 'cask "steam"' 'cask "slack"'
  installed <<'DUMP'
brew "jq"
cask "slack"
DUMP
  run brewfile-sync
  [[ $output == *"Missing: none"* ]] || false
}

@test "Missing: a personal machine is held to the personal list, not the work one" {
  MACHINE=personal lists 'brew "jq"' 'cask "steam"' 'cask "slack"'
  installed <<<'brew "jq"'
  run brewfile-sync
  [[ $output == "Machine type: personal"* ]] || false
  [[ $output == *'  cask "steam"'* ]] || false
  [[ $output != *'cask "slack"'* ]] || false
}

@test "it only reads: brew is asked for the dump and nothing else, and the lists are untouched" {
  lists 'brew "jq"' '' ''
  installed <<<'brew "ripgrep"'
  before=$(cat "$SRC"/.chezmoitemplates/*)
  run brewfile-sync
  [ "$status" -eq 0 ]
  [ "$(stub brew calls)" = "bundle dump --file=-" ]
  [ "$(cat "$SRC"/.chezmoitemplates/*)" = "$before" ]
}
