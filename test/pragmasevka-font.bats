#!/usr/bin/env bats
#
# Tests for run_onchange_after_pragmasevka-font.sh, which installs the Pragmasevka
# Nerd Font from its GitHub release on a chezmoi apply. It runs straight from the
# repo, as chezmoi runs it, against a stubbed curl that serves a fixture zip.

bats_require_minimum_version 1.5.0
load harness

run_script() { run in_sandbox sh "$REPO_ROOT/run_onchange_after_pragmasevka-font.sh"; }

release=https://github.com/shytikov/pragmasevka/releases/download/v1.7.0/Pragmasevka_NF.zip

# release FILE...: the release zip holds these files, each containing its own name.
release() {
  local dir=$SANDBOX/release name
  mkdir -p "$dir"
  for name in "$@"; do printf '%s\n' "$name" >"$dir/$name"; done
  (cd "$dir" && zip -q release.zip "$@")
  stub curl serve "$release" "$dir/release.zip"
}

@test "installs the release's fonts into a folder of their own under the user fonts" {
  release pragmasevka-nf-regular.ttf pragmasevka-nf-bold.ttf
  run_script
  [ "$status" -eq 0 ]
  fonts=$HOME/Library/Fonts/Pragmasevka\ NF
  [ "$(ls "$fonts")" = "pragmasevka-nf-bold.ttf
pragmasevka-nf-regular.ttf" ]
  [ "$(cat "$fonts/pragmasevka-nf-regular.ttf")" = pragmasevka-nf-regular.ttf ]
}


@test "replaces an earlier install, so a font the release dropped does not linger" {
  fonts=$HOME/Library/Fonts/Pragmasevka\ NF
  mkdir -p "$fonts"
  echo 'an earlier version' >"$fonts/pragmasevka-nf-regular.ttf"
  echo 'an earlier version' >"$fonts/pragmasevka-nf-light.ttf"
  release pragmasevka-nf-regular.ttf
  run_script
  [ "$status" -eq 0 ]
  [ "$(ls "$fonts")" = pragmasevka-nf-regular.ttf ]
  [ "$(cat "$fonts/pragmasevka-nf-regular.ttf")" = pragmasevka-nf-regular.ttf ]
}

@test "fails when the download fails, so the apply fails, and keeps the fonts already installed" {
  fonts=$HOME/Library/Fonts/Pragmasevka\ NF
  mkdir -p "$fonts"
  echo 'an earlier version' >"$fonts/pragmasevka-nf-regular.ttf"
  run_script
  [ "$status" -ne 0 ]
  [[ $output == *"returned error: 404"* ]] || false
  [ "$(cat "$fonts/pragmasevka-nf-regular.ttf")" = 'an earlier version' ]
}

@test "installs only the fonts, not the rest of the archive" {
  release pragmasevka-nf-regular.ttf LICENSE.txt
  run_script
  [ "$status" -eq 0 ]
  [ "$(ls "$HOME/Library/Fonts/Pragmasevka NF")" = pragmasevka-nf-regular.ttf ]
}

