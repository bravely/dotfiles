#!/usr/bin/env bats
#
# Tests for the harness itself: the promises that no test can touch the real
# machine. If one of these fails, trust no other result.

load harness

# What HOME and BASH_ENV were before this file's own sandbox replaced them: the
# values setup_suite.bash left for every test, loaded harness or not.
setup_file() {
  OUTER_HOME=$HOME OUTER_BASH_ENV=${BASH_ENV-}
  export OUTER_HOME OUTER_BASH_ENV
}

# The real file a path ends up at, through any number of symlinks.
resolve() {
  local path=$1
  while [ -L "$path" ]; do path=$(readlink "$path"); done
  printf '%s\n' "$path"
}

@test "suite: a test file starts with a throwaway HOME and no BASH_ENV, before it builds anything" {
  [ "$(cd "$OUTER_HOME" && pwd -P)" = "$(cd "$BATS_SUITE_TMPDIR" && pwd -P)/guard-home" ]
  [ -z "$OUTER_BASH_ENV" ]
}

@test "scripts inherit none of the caller's environment" {
  export BASH_ENV=/real/shell-env.sh ZDOTDIR=/real/zdotdir XDG_CONFIG_HOME=/real/config \
         GH_TOKEN=ghp_real STARSHIP_CONFIG=/real/starship.toml ANTHROPIC_API_KEY=sk-real \
         HOMEBREW_PREFIX=/opt/homebrew SSH_AUTH_SOCK=/real/agent
  run in_sandbox env
  [ "$status" -eq 0 ]
  for name in BASH_ENV ZDOTDIR XDG_CONFIG_HOME GH_TOKEN STARSHIP_CONFIG ANTHROPIC_API_KEY HOMEBREW_PREFIX SSH_AUTH_SOCK; do
    [[ $output != *"$name="* ]] || false
  done
}

@test "scripts get a HOME inside this test's own tmpdir" {
  run in_sandbox sh -c 'printf %s "$HOME"'
  [ "$output" = "$(cd "$BATS_TEST_TMPDIR" && pwd -P)/home" ]
}

@test "each test gets its own copy of the installed scripts" {
  echo "# scribble" >>"$HOME/.local/bin/claude-rc"
  run grep -c scribble "$HOME/.local/bin/claude-rc" "$SUITE_HOME/.local/bin/claude-rc"
  [ "$output" = "$HOME/.local/bin/claude-rc:1
$SUITE_HOME/.local/bin/claude-rc:0" ]
}

@test "launchctl, gh, brew, claude, starship and sleep resolve to stubs and to nothing else" {
  for tool in launchctl gh brew claude starship sleep; do
    run in_sandbox sh -c 'IFS=:; for dir in $PATH; do [ -e "$dir/'$tool'" ] && echo "$dir/'$tool'"; done'
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    while read -r found; do
      [ "$(resolve "$found")" = "$BATS_TEST_DIRNAME/stubs/$tool" ]
    done <<<"$output"
  done
}

@test "a tool nobody listed does not exist: no curl, ssh, osascript or open" {
  for tool in curl wget ssh nc osascript open; do
    run in_sandbox sh -c "command -v $tool"
    [ "$status" -ne 0 ]
  done
}

@test "hide removes a tool for the rest of the test and leaves the suite's copy alone" {
  hide jq
  run in_sandbox sh -c 'command -v jq'
  [ "$status" -ne 0 ]
  [ -e "$SUITE_TOOLS/jq" ]
}

@test "a stub refuses to run outside a sandbox" {
  run env -i PATH=/usr/bin:/bin STUB_HOME="$BATS_TEST_DIRNAME/stubs" "$BATS_TEST_DIRNAME/stubs/launchctl" print gui/1/x
  [ "$status" -eq 99 ]
  [[ $output == *"no sandbox"* ]] || false
}

@test "a stub fails closed on a call it does not model, and teardown reports it" {
  run in_sandbox launchctl frobnicate
  [ "$status" -eq 99 ]
  [[ $output == *"unexpected call: frobnicate"* ]] || false
  run sandbox_check
  [ "$status" -eq 1 ]
  rm "$STUB_STATE/unexpected"   # this test provoked it on purpose
}

@test "a stub rejects a verb it does not have" {
  run stub launchctl nonsense
  [ "$status" -eq 2 ]
}

@test "stub fail makes matching calls fail and leaves the others alone" {
  stub launchctl fail 'kickstart' 7 'kickstart refused'
  run in_sandbox launchctl kickstart -k gui/1/x
  [ "$status" -eq 7 ]
  [[ $output == *"kickstart refused"* ]] || false
  run in_sandbox launchctl print gui/1/x
  [ "$status" -eq 113 ]
}

@test "stub calls lists every call in order, quoting awkward arguments" {
  in_sandbox gh auth status >/dev/null
  in_sandbox gh api repos/a/b --jq '.a | .b' >/dev/null
  run stub gh calls
  [ "$output" = "auth status
api repos/a/b --jq .a\\ \\|\\ .b" ]
}

@test "git in the sandbox has a fixed identity and never signs" {
  run in_sandbox git config user.email
  [ "$output" = test@dotfiles.test ]
  run in_sandbox git config commit.gpgsign
  [ "$output" = false ]
}

@test "git cannot use a network protocol" {
  run in_sandbox git ls-remote https://github.com/bravely/dotfiles.git
  [ "$status" -ne 0 ]
  [[ $output == *"not allowed"* ]] || false
}

@test "tools that honour proxy settings are pointed at a closed port" {
  run in_sandbox sh -c 'printf %s "$HTTPS_PROXY"'
  [ "$output" = http://127.0.0.1:9 ]
}

@test "in_sandbox refuses when no sandbox was built" {
  unset SANDBOX
  run in_sandbox true
  [ "$status" -eq 99 ]
}

@test "in_sandbox refuses when HOME has been pointed outside the sandbox" {
  HOME=/somewhere/else run in_sandbox true
  [ "$status" -eq 99 ]
}

@test "a command is not handed the caller's terminal or socket as stdin" {
  run in_sandbox sh -c 'cat'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a command is handed the test's stdin when that is a pipe or file" {
  run in_sandbox sh -c 'cat' <<<"from the test"
  [ "$output" = "from the test" ]
}

@test "the kernel refuses a write outside the test's own sandbox" {
  run in_sandbox sh -c "echo x >'$BATS_SUITE_TMPDIR/outside-canary'"
  [ "$status" -ne 0 ]
  [[ $output == *"Operation not permitted"* ]] || false
  [ ! -e "$BATS_SUITE_TMPDIR/outside-canary" ]
}

@test "the kernel refuses to read or write the real HOME, but not the repo under test" {
  # The profile is tested against a stand-in for the real HOME, so a broken profile
  # exposes a fixture and not the actual one.
  fake_real_home=$(cd "$BATS_SUITE_TMPDIR" && pwd -P)/fake-real-home   # resolved, as the profile needs
  mkdir -p "$fake_real_home/.config"
  echo '{"secret": true}' >"$fake_real_home/.claude.json"
  confined() {
    /usr/bin/sandbox-exec -D "ROOT=$SANDBOX" -D "REAL_HOME=$fake_real_home" -D "REPO=$fake_real_home/dev/repo" \
      -f "$SUITE_PROFILE" "$@"
  }
  mkdir -p "$fake_real_home/dev/repo" && echo readme >"$fake_real_home/dev/repo/README.md"
  run confined cat "$fake_real_home/.claude.json"
  [ "$status" -ne 0 ]
  [[ $output == *"Operation not permitted"* ]] || false
  run confined sh -c "echo x >'$fake_real_home/.config/planted'"
  [ "$status" -ne 0 ]
  run confined cat "$fake_real_home/dev/repo/README.md"
  [ "$output" = readme ]
}

@test "the kernel refuses to run the real launchctl, even by absolute path" {
  run in_sandbox /bin/launchctl version
  [ "$status" -ne 0 ]
  [[ $output == *"Operation not permitted"* ]] || false
}

@test "the kernel refuses a network connection, not just a proxy setting" {
  run in_sandbox bash -c 'exec 3<>/dev/tcp/127.0.0.1/9'
  [ "$status" -ne 0 ]
  [[ $output != *"Connection refused"* ]] || false
}

@test "a test starts in the sandbox's HOME, not in the checkout" {
  [ "$PWD" = "$HOME" ]
}
