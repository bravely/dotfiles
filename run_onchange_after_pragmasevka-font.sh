#!/bin/sh
#
# Install Pragmasevka, the Nerd Font build, which has no Homebrew cask. Its
# release's .ttf files go in a folder of their own under the user fonts
# directory, where macOS picks them up. chezmoi runs this again only when this
# file changes, so bump the version in the URL to upgrade.

set -eu

url=https://github.com/shytikov/pragmasevka/releases/download/v1.7.0/Pragmasevka_NF.zip
fonts="$HOME/Library/Fonts/Pragmasevka NF"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pragmasevka.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/release.zip" "$url"
unzip -q "$tmp/release.zip" '*.ttf' -d "$tmp/fonts"
mkdir -p "${fonts%/*}"
rm -rf "$fonts"
mv "$tmp/fonts" "$fonts"
