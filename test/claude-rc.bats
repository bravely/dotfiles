#!/usr/bin/env bats
#
# Tests for dot_local/bin/executable_claude-rc, which keeps a `claude
# remote-control` server running per repo as a LaunchAgent. The script runs as
# chezmoi installs it, against a stubbed launchctl that remembers what is loaded,
# a stubbed claude, and the real plutil, jq and git, all inside the sandbox
# (harness.bash).

bats_require_minimum_version 1.5.0
load harness

PREFIX=com.bravely.claude-remote-control
UPDATER=com.bravely.claude-rc-updater

setup() {
  sandbox_init
  echo '{"remoteDialogSeen": true}' >"$HOME/.claude.json"   # Remote Control enabled on this Mac
}

# git_repo PATH: a checkout with one commit at ~/PATH. Prints its path.
git_repo() {
  mkdir -p "$HOME/$1"
  in_sandbox git -C "$HOME/$1" init -q || return 1
  in_sandbox git -C "$HOME/$1" commit -q --allow-empty -m init || return 1
  echo "$HOME/$1"
}

# git_worktree REPO PATH BRANCH: a linked worktree of REPO at ~/PATH.
git_worktree() {
  in_sandbox git -C "$1" worktree add -q "$HOME/$2" -b "$3" || return 1
  echo "$HOME/$2"
}

# git_submodule PARENT PATH: a submodule of PARENT at PARENT/PATH. Prints its path.
git_submodule() {
  local upstream
  upstream=$(git_repo "upstream-of-${2//\//-}") || return 1
  in_sandbox git -C "$1" submodule add -q "$upstream" "$2" || return 1
  echo "$1/$2"
}

# trust DIR...: the folder-trust prompt was accepted there.
trust() {
  local dir json
  json=$(cat "$HOME/.claude.json")
  for dir in "$@"; do
    json=$(jq --arg d "$dir" '.projects[$d] = {hasTrustDialogAccepted: true}' <<<"$json")
  done
  printf '%s\n' "$json" >"$HOME/.claude.json"
}

# serve NAME: a trusted checkout at ~/dev/NAME whose server is installed. Prints its path.
# Callers run it in $(...), where bash 3.2 does not stop at a failing command, so every
# step here returns explicitly.
serve() {
  local dir
  dir=$(git_repo "dev/$1") || return 1
  trust "$dir" || return 1
  run claude-rc ensure "$dir"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  echo "$dir"
}

# label_for NAME: the label of the server for ~/dev/NAME.
label_for() { echo "$PREFIX.dev-${1//\//-}"; }

agents() { echo "$HOME/Library/LaunchAgents"; }

# What reached launchd, other than looking: the calls that change what is loaded.
mutations() { stub launchctl calls | grep -E '^(bootstrap|bootout|kickstart)' || true; }

plist_field() { plutil -extract "$2" raw -o - "$1"; }

@test "usage: no command prints usage on stderr and exits 2" {
  run --separate-stderr claude-rc
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ $stderr == "Usage: claude-rc ensure"* ]] || false
}

@test "usage: --help prints usage on stdout and exits 0" {
  run --separate-stderr claude-rc --help
  [ "$status" -eq 0 ]
  [[ $output == "Usage: claude-rc ensure"* ]] || false
  [ -z "$stderr" ]
}

@test "usage: an unknown command exits 2" {
  run claude-rc bounce
  [ "$status" -eq 2 ]
}

@test "usage: ensure with two directories exits 2" {
  run claude-rc ensure /a /b
  [ "$status" -eq 2 ]
}

@test "usage: status takes no directory" {
  run claude-rc status /a
  [ "$status" -eq 2 ]
}

@test "refuses when jq is not installed" {
  hide jq
  run claude-rc status
  [ "$status" -eq 1 ]
  [[ $output == *"jq is not installed"* ]] || false
}

@test "refuses when claude is not installed in ~/.local/bin" {
  rm "$HOME/.local/bin/claude"
  run claude-rc status
  [ "$status" -eq 1 ]
  [[ $output == *"claude not found at $HOME/.local/bin/claude"* ]] || false
}

@test "a plain checkout is served as itself" {
  repo=$(git_repo dev/dotfiles)
  trust "$repo"
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  [ "$(plist_field "$(agents)/$(label_for dotfiles).plist" WorkingDirectory)" = "$repo" ]
}

@test "ensure with no directory serves the one it is run in" {
  repo=$(git_repo dev/dotfiles)
  trust "$repo"
  cd "$repo"
  run claude-rc ensure
  [ "$status" -eq 0 ]
  [[ $output == "claude-rc: $repo: started."* ]] || false
}

@test "a subdirectory serves the checkout that contains it" {
  repo=$(git_repo dev/dotfiles)
  trust "$repo"
  mkdir "$repo/src"
  run claude-rc ensure "$repo/src"
  [ "$status" -eq 0 ]
  [ "$(plist_field "$(agents)/$(label_for dotfiles).plist" WorkingDirectory)" = "$repo" ]
}

@test "a linked worktree serves its main checkout, so all of a repo's worktrees share one server" {
  repo=$(git_repo dev/dotfiles)
  worktree=$(git_worktree "$repo" dev/dotfiles-wip wip)
  trust "$repo"
  run claude-rc ensure "$worktree"
  [ "$status" -eq 0 ]
  [ "$(plist_field "$(agents)/$(label_for dotfiles).plist" WorkingDirectory)" = "$repo" ]
  [ "$(ls "$(agents)" | grep -c "^$PREFIX\.")" -eq 1 ]
}

@test "a submodule is served as itself, not as the repo that holds it" {
  parent=$(git_repo dev/parent)
  sub=$(git_submodule "$parent" libs/sub)
  trust "$sub"
  run claude-rc ensure "$sub"
  [ "$status" -eq 0 ]
  [ "$(plist_field "$(agents)/$(label_for parent/libs/sub).plist" WorkingDirectory)" = "$sub" ]
}

@test "a directory outside any checkout is refused" {
  mkdir -p "$HOME/dev/notes"
  run claude-rc ensure "$HOME/dev/notes"
  [ "$status" -eq 1 ]
  [[ $output == *"is not inside a git checkout"* ]] || false
}

# Nothing reached the machine: no agents directory, nothing loaded.
nothing_installed() {
  [ ! -e "$(agents)" ]
  [ -z "$(stub launchctl loaded-labels)" ]
  [ -z "$(mutations)" ]
}

@test "refuses when claude is not logged in" {
  repo=$(git_repo dev/dotfiles)
  trust "$repo"
  stub claude logged-out
  run claude-rc ensure "$repo"
  [ "$status" -eq 1 ]
  [[ $output == *"not logged in"* ]] || false
  nothing_installed
}

@test "refuses a folder that has not been trusted" {
  repo=$(git_repo dev/dotfiles)
  run claude-rc ensure "$repo"
  [ "$status" -eq 1 ]
  [[ $output == *"hasn't been trusted yet"* ]] || false
  nothing_installed
}

@test "refuses a folder whose trust was declined, not just never asked" {
  repo=$(git_repo dev/dotfiles)
  jq --arg d "$repo" '.projects[$d] = {hasTrustDialogAccepted: false}' "$HOME/.claude.json" >"$HOME/c.json"
  mv "$HOME/c.json" "$HOME/.claude.json"
  run claude-rc ensure "$repo"
  [ "$status" -eq 1 ]
  [[ $output == *"hasn't been trusted yet"* ]] || false
}

@test "accepts a folder trusted through an ancestor" {
  repo=$(git_repo dev/dotfiles)
  trust "$HOME/dev"
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
}

@test "refuses when there is no ~/.claude.json at all" {
  repo=$(git_repo dev/dotfiles)
  rm "$HOME/.claude.json"
  run claude-rc ensure "$repo"
  [ "$status" -eq 1 ]
  [[ $output == *"hasn't been trusted yet"* ]] || false
  nothing_installed
}

@test "refuses until Remote Control has been enabled on this Mac" {
  repo=$(git_repo dev/dotfiles)
  echo '{}' >"$HOME/.claude.json"
  trust "$repo"
  run claude-rc ensure "$repo"
  [ "$status" -eq 1 ]
  [[ $output == *"Remote Control hasn't been enabled"* ]] || false
  nothing_installed
}

@test "ensure installs the server's agent, loads it, and says where the log is" {
  repo=$(git_repo dev/dotfiles)
  trust "$repo"
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  [[ $output == *"claude-rc: $repo: started. Log: $HOME/Library/Logs/claude-rc-dev-dotfiles.log"* ]] || false
  [[ $(stub launchctl loaded-labels) == *"$(label_for dotfiles)"* ]] || false
  [ -f "$(agents)/$(label_for dotfiles).plist" ]
}

@test "the agent runs claude remote-control in the repo, per-session worktrees, auto permissions" {
  repo=$(serve dotfiles)
  plist=$(agents)/$(label_for dotfiles).plist
  run plutil -lint -s "$plist"
  [ "$status" -eq 0 ]
  [ "$(plist_field "$plist" Label)" = "$(label_for dotfiles)" ]
  [ "$(plist_field "$plist" WorkingDirectory)" = "$repo" ]
  [ "$(plutil -extract ProgramArguments json -o - "$plist" | jq -r 'join(" ")')" = \
    "$HOME/.local/bin/claude remote-control --spawn=worktree --permission-mode auto --no-create-session-in-dir --name dotfiles" ]
}

@test "the agent starts at login and is restarted if it dies" {
  serve dotfiles >/dev/null
  plist=$(agents)/$(label_for dotfiles).plist
  [ "$(plist_field "$plist" RunAtLoad)" = true ]
  [ "$(plist_field "$plist" KeepAlive)" = true ]
}

@test "the agent's log is ~/Library/Logs/claude-rc-<slug>.log" {
  serve dotfiles >/dev/null
  [ "$(plist_field "$(agents)/$(label_for dotfiles).plist" StandardOutPath)" = "$HOME/Library/Logs/claude-rc-dev-dotfiles.log" ]
}

@test "paths with & < > are escaped in the agent, and read back unchanged" {
  repo=$(git_repo 'dev/a&b<c>')
  trust "$repo"
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  plist=$(agents)/$PREFIX.dev-a-b-c-.plist
  run plutil -lint -s "$plist"
  [ "$status" -eq 0 ]
  [ "$(plist_field "$plist" WorkingDirectory)" = "$repo" ]
  [ "$(plutil -extract ProgramArguments json -o - "$plist" | jq -r '.[-1]')" = 'a&b<c>' ]
}

@test "the first ensure also installs and loads the updater, and says so" {
  repo=$(git_repo dev/dotfiles)
  trust "$repo"
  run claude-rc ensure "$repo"
  [[ $output == *"claude-rc: updater installed; it restarts servers when claude updates"* ]] || false
  [[ $(stub launchctl loaded-labels) == *"$UPDATER"* ]] || false
}

@test "the updater runs restart --all whenever ~/.local/bin/claude changes" {
  serve dotfiles >/dev/null
  plist=$(agents)/$UPDATER.plist
  [ "$(plutil -extract ProgramArguments json -o - "$plist" | jq -r 'join(" ")')" = "$HOME/.local/bin/claude-rc restart --all" ]
  [ "$(plutil -extract WatchPaths json -o - "$plist" | jq -r '.[]')" = "$HOME/.local/bin/claude" ]
}

@test "the label is the path under HOME with slashes and spaces turned into dashes" {
  repo=$(git_repo 'dev/my repo')
  trust "$repo"
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  [ -f "$(agents)/$PREFIX.dev-my-repo.plist" ]
}

@test "two paths that flatten to the same slug get distinct labels" {
  first=$(serve foo-bar)
  second=$(git_repo dev/foo/bar)
  trust "$second"
  run claude-rc ensure "$second"
  [ "$status" -eq 0 ]
  [ "$(ls "$(agents)" | grep -c "^$PREFIX\.")" -eq 2 ]
  collided=$(ls "$(agents)" | grep -E "^$PREFIX\.dev-foo-bar-[0-9a-f]{8}\.plist$")
  [ "$(plist_field "$(agents)/$collided" WorkingDirectory)" = "$second" ]
  [ "$(plist_field "$(agents)/$(label_for foo-bar).plist" WorkingDirectory)" = "$first" ]
}

@test "a second ensure reuses the repo's label rather than minting another" {
  repo=$(serve dotfiles)
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  [ "$(ls "$(agents)" | grep -c "^$PREFIX\.")" -eq 1 ]
}

@test "ensure is a no-op for a server that is up to date and running" {
  repo=$(serve dotfiles)
  before=$(mutations)
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  [[ $output =~ "claude-rc: $repo: already running (pid "[0-9]+")" ]] || false
  [ "$(mutations)" = "$before" ]
}

@test "ensure says launchd is about to start a server that is loaded but not running yet" {
  repo=$(serve dotfiles)
  stub launchctl loaded "$(label_for dotfiles)"
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  [[ $output == *"claude-rc: $repo: loaded; launchd is about to start it. Log: "* ]] || false
}

@test "ensure exits 1 for a server that is loaded but failing, and points at the log" {
  repo=$(serve dotfiles)
  stub launchctl loaded "$(label_for dotfiles)" exit=78
  run claude-rc ensure "$repo"
  [ "$status" -eq 1 ]
  [[ $output == *"loaded but failing (last exit 78)"* ]] || false
  [[ $output == *"See $HOME/Library/Logs/claude-rc-dev-dotfiles.log"* ]] || false
}

@test "ensure still repairs the updater when the server is failing" {
  repo=$(serve dotfiles)
  stub launchctl loaded "$(label_for dotfiles)" exit=78
  rm "$(agents)/$UPDATER.plist"
  run claude-rc ensure "$repo"
  [ "$status" -eq 1 ]
  [ -f "$(agents)/$UPDATER.plist" ]
}

@test "ensure loads a server whose agent is installed but not loaded" {
  repo=$(serve dotfiles)
  in_sandbox launchctl bootout "$DOMAIN/$(label_for dotfiles)"
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  [[ $output == *"$repo: started."* ]] || false
  [[ $(stub launchctl loaded-labels) == *"$(label_for dotfiles)"* ]] || false
}

# An agent written by an older version of the script, as launchd has it loaded.
make_stale() {
  sed 's/--permission-mode/--permission-mode-old/' "$1" >"$1.old"
  mv "$1.old" "$1"
}

@test "ensure rewrites and reloads an agent that differs from what the script writes now" {
  repo=$(serve dotfiles)
  plist=$(agents)/$(label_for dotfiles).plist
  make_stale "$plist"
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  [[ $output == *"$repo: started."* ]] || false
  [ "$(plutil -extract ProgramArguments json -o - "$plist" | jq -r '.[3]')" = --permission-mode ]
  [ "$(mutations | tail -2)" = "bootout $DOMAIN/$(label_for dotfiles)
bootstrap $DOMAIN $plist" ]
}

@test "ensure waits for launchd to finish unloading before it loads the new agent" {
  repo=$(serve dotfiles)
  make_stale "$(agents)/$(label_for dotfiles).plist"
  stub launchctl unload-lag 3
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  [[ $(stub launchctl loaded-labels) == *"$(label_for dotfiles)"* ]] || false
  [ -n "$(stub sleep calls)" ]   # it did wait, so the run above exercised the wait
}

@test "ensure gives up, and loads nothing, when launchd never finishes unloading" {
  repo=$(serve dotfiles)
  make_stale "$(agents)/$(label_for dotfiles).plist"
  stub launchctl unload-lag forever
  before=$(mutations)
  run claude-rc ensure "$repo"
  [ "$status" -eq 1 ]
  [[ $output == *"launchd is still unloading $(label_for dotfiles)"* ]] || false
  [ "$(mutations)" = "$before
bootout $DOMAIN/$(label_for dotfiles)" ]
}

@test "ensure exits 1 when launchctl cannot load the agent" {
  repo=$(git_repo dev/dotfiles)
  trust "$repo"
  stub launchctl fail bootstrap 5 'Bootstrap failed: 5: Input/output error'
  run claude-rc ensure "$repo"
  [ "$status" -eq 1 ]
  [[ $output == *"launchctl could not load $(agents)/$(label_for dotfiles).plist"* ]] || false
}

@test "ensure warns, and still succeeds, when ~/.local/bin/claude-rc is not installed" {
  repo=$(git_repo dev/dotfiles)
  trust "$repo"
  rm "$HOME/.local/bin/claude-rc"
  run claude-rc ensure "$repo"
  [ "$status" -eq 0 ]
  [[ $output == *"warning: updater: $HOME/.local/bin/claude-rc is missing (run: chezmoi apply)"* ]] || false
}

@test "status with no servers says so and exits 0" {
  run claude-rc status
  [ "$status" -eq 0 ]
  [ "$output" = "claude-rc: no servers installed" ]
}

@test "status shows a running server's pid and a loaded updater" {
  repo=$(serve dotfiles)
  stub launchctl loaded "$(label_for dotfiles)" pid=777
  run claude-rc status
  [ "$status" -eq 0 ]
  [ "$output" = "$repo: running (pid 777)
updater: loaded" ]
}

@test "status shows a server that is loaded but not running" {
  repo=$(serve dotfiles)
  stub launchctl loaded "$(label_for dotfiles)"
  run claude-rc status
  [[ $output == "$repo: loaded, not running"* ]] || false
}

@test "status shows a server that is installed but not loaded" {
  repo=$(serve dotfiles)
  in_sandbox launchctl bootout "$DOMAIN/$(label_for dotfiles)"
  run claude-rc status
  [ "$status" -eq 0 ]
  [[ $output == "$repo: not loaded (run: claude-rc ensure in the repo)"* ]] || false
}

@test "status shows the last exit code and the log for a failing server" {
  repo=$(serve dotfiles)
  stub launchctl loaded "$(label_for dotfiles)" exit=78
  run claude-rc status
  [ "$status" -eq 0 ]
  [[ $output == "$repo: loaded, not running; last exit 78, see $HOME/Library/Logs/claude-rc-dev-dotfiles.log"* ]] || false
}

@test "status flags a server whose directory is gone and says how to remove it" {
  repo=$(serve dotfiles)
  rm -rf "$repo"
  run claude-rc status
  [ "$status" -eq 0 ]
  [[ $output == *"directory is gone (run: claude-rc remove '$repo')"* ]] || false
}

@test "status lists every server" {
  one=$(serve alpha)
  two=$(serve beta)
  run claude-rc status
  [[ $output == *"$one: running"* ]] || false
  [[ $output == *"$two: running"* ]] || false
}

@test "status says when the updater is not loaded" {
  serve dotfiles >/dev/null
  in_sandbox launchctl bootout "$DOMAIN/$UPDATER"
  run claude-rc status
  [[ $output == *"updater: not loaded (run: claude-rc ensure in any served repo)"* ]] || false
}

@test "status says when the installed claude-rc is missing" {
  serve dotfiles >/dev/null
  rm "$HOME/.local/bin/claude-rc"
  run claude-rc status
  [[ $output == *"updater: $HOME/.local/bin/claude-rc is missing (run: chezmoi apply), so servers won't restart when claude updates"* ]] || false
}

@test "restart kickstarts the repo's server" {
  repo=$(serve dotfiles)
  run claude-rc restart "$repo"
  [ "$status" -eq 0 ]
  [ "$output" = "claude-rc: $repo: restarted" ]
  [ "$(mutations | tail -1)" = "kickstart -k $DOMAIN/$(label_for dotfiles)" ]
}

@test "restart --all kickstarts every server and not the updater" {
  serve alpha >/dev/null
  serve beta >/dev/null
  run claude-rc restart --all
  [ "$status" -eq 0 ]
  [ "$(mutations | grep -c '^kickstart')" -eq 2 ]
  [[ $(mutations) != *"kickstart -k $DOMAIN/$UPDATER"* ]] || false
}

@test "restart skips a server that is not loaded, says so, and exits 1" {
  repo=$(serve dotfiles)
  in_sandbox launchctl bootout "$DOMAIN/$(label_for dotfiles)"
  run claude-rc restart "$repo"
  [ "$status" -eq 1 ]
  [[ $output == *"$repo: not loaded, skipped (run: claude-rc ensure in the repo)"* ]] || false
  [[ $(mutations) != *kickstart* ]] || false
}

@test "restart --all restarts the servers it can and still exits 1 for one that is not loaded" {
  serve alpha >/dev/null
  serve beta >/dev/null
  in_sandbox launchctl bootout "$DOMAIN/$(label_for alpha)"
  run claude-rc restart --all
  [ "$status" -eq 1 ]
  [ "$(mutations | grep -c '^kickstart')" -eq 1 ]
  [[ $(mutations) == *"kickstart -k $DOMAIN/$(label_for beta)"* ]] || false
}

@test "restart exits 1 for a repo that has no server" {
  repo=$(git_repo dev/dotfiles)
  run claude-rc restart "$repo"
  [ "$status" -eq 1 ]
  [[ $output == *"has no server (run: claude-rc ensure)"* ]] || false
}

@test "remove unloads the server and deletes its agent" {
  repo=$(serve dotfiles)
  run claude-rc remove "$repo"
  [ "$status" -eq 0 ]
  [[ $output == *"claude-rc: $repo: removed"* ]] || false
  [ ! -e "$(agents)/$(label_for dotfiles).plist" ]
  [[ $(stub launchctl loaded-labels) != *"$(label_for dotfiles)"* ]] || false
}

@test "remove works on a repo that has since been deleted" {
  repo=$(serve dotfiles)
  rm -rf "$repo"
  run claude-rc remove "$repo"
  [ "$status" -eq 0 ]
  [[ $output == *"$repo: removed"* ]] || false
  [ ! -e "$(agents)/$(label_for dotfiles).plist" ]
}

@test "remove of a repo with no server says so and exits 0" {
  repo=$(git_repo dev/dotfiles)
  run claude-rc remove "$repo"
  [ "$status" -eq 0 ]
  [ "$output" = "claude-rc: $repo: no server installed" ]
}

@test "removing the last server removes the updater too" {
  repo=$(serve dotfiles)
  run claude-rc remove "$repo"
  [[ $output == *"claude-rc: removed the updater"* ]] || false
  [ ! -e "$(agents)/$UPDATER.plist" ]
  [ -z "$(stub launchctl loaded-labels)" ]
}

@test "removing one of several servers keeps the updater" {
  keep=$(serve alpha)
  drop=$(serve beta)
  run claude-rc remove "$drop"
  [ "$status" -eq 0 ]
  [[ $output != *"removed the updater"* ]] || false
  [ -f "$(agents)/$UPDATER.plist" ]
  [[ $(stub launchctl loaded-labels) == *"$UPDATER"* ]] || false
  [[ $(stub launchctl loaded-labels) == *"$(label_for alpha)"* ]] || false
}
