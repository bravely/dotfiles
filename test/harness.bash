# Shared harness. Every test file starts with `load harness`.
#
# Loading it gives a test file, with no further setup:
#
#   setup / teardown   build a sandbox and check that no stub saw a call it does not
#                      model. A file with its own setup() calls sandbox_init in it.
#   claude-rc, gh-repo-profile, brewfile-sync, statusline
#                      functions named after the scripts, which run the script as
#                      chezmoi installs it, inside the sandbox. `run claude-rc ensure`
#                      reads as the command line.
#   in_sandbox CMD...  anything else, through the same gateway.
#   stub TOOL VERB..   configure or read back a stub: `stub gh route rulesets <<JSON`,
#                      `stub launchctl calls`.
#   hide TOOL...       the tool is not installed for the rest of the test.
#   chezmoi_source, chezmoi_config, chezmoi_apply, render
#                      the real chezmoi, pointed at this repo (or a fixture) from the
#                      sandbox's HOME, with no flag on any call.
#
# Isolation is structural, in four layers:
#   1. Scripts run under `env -i`, so they inherit nothing: HOME is a copy of a golden
#      home inside the test's own tmpdir, PATH names only two directories.
#   2. That PATH holds symlinks to a short list of real tools (setup_suite.bash) and
#      to the stubs. launchctl, gh, brew and claude are stubs; the real ones are on
#      no directory a script can see. A tool nobody listed does not exist.
#   3. setup_suite.bash gives the whole run a throwaway HOME before any test starts,
#      so a test file that forgets all of this still cannot reach the real one.
#   4. The kernel enforces it: every in_sandbox command runs under a macOS seatbelt
#      profile (suite_write_profile below) that denies any write outside the test's
#      tmpdir, any read or write in the real HOME except the repo under test, running
#      the real launchctl, and the network. A script that reaches for an absolute path,
#      or builds one, is refused by the OS, not by a convention.

REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)

# Real tools the scripts under test and the fixtures may use. Anything not named here
# does not exist for them: a script that starts using a new tool fails the suite
# until the tool is added here, on purpose.
suite_real_tools=(
  awk bash cat chezmoi cmp cut env git grep head id jq mkdir mv plutil rm sed sh shasum tr zsh
)

setup()    { sandbox_init; }
teardown() { sandbox_check; }

# sandbox_init [ROOT]
# Everything a test can touch lives under ROOT (default: the test's own tmpdir):
#   $HOME        a copy of the golden home: the scripts as chezmoi installs them,
#                the claude stub at ~/.local/bin/claude, a git identity that never signs
#   $STUB_STATE  where the stubs keep their state
#   $SANDBOX/tmp TMPDIR for the scripts
# ROOT is resolved with pwd -P: macOS's /var is /private/var, and git, zsh and
# claude-rc's `${root#$HOME/}` all see the resolved form.
sandbox_init() {
  mkdir -p "${1:-$BATS_TEST_TMPDIR}"
  SANDBOX=$(cd "${1:-$BATS_TEST_TMPDIR}" && pwd -P)
  export HOME=$SANDBOX/home
  STUB_STATE=$SANDBOX/stub-state
  SANDBOX_PATH=$HOME/.local/bin:${SUITE_TOOLS:?setup_suite.bash did not run}
  # shellcheck disable=SC2034 # read by the test files that load this one
  DOMAIN=gui/$(id -u)
  mkdir -p "$HOME" "$STUB_STATE" "$SANDBOX/tmp"
  [ -z "${SUITE_HOME:-}" ] || cp -R "$SUITE_HOME/." "$HOME/"
  # A test starts where a user's shell would: in HOME. A relative path in a test, or a
  # script's temp file (bash 3.2 puts here-documents in the cwd under the seatbelt), lands
  # in the sandbox, never in the repo checkout.
  cd "$HOME" || return 1
  # The test process itself is scrubbed too, so a stray `git` in a test body is as
  # contained as one run through in_sandbox.
  unset BASH_ENV ENV ZDOTDIR XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
  export GIT_CONFIG_GLOBAL=${SUITE_GITCONFIG:-$HOME/.gitconfig} GIT_CONFIG_NOSYSTEM=1
}

# sandbox_check: fails the test if a stub was called in a way it does not model.
# Such a call already exited 99, but a script may have swallowed that.
sandbox_check() {
  [ -s "$STUB_STATE/unexpected" ] || return 0
  echo "a stub saw a call it does not model:" >&2
  cat "$STUB_STATE/unexpected" >&2
  return 1
}

# in_sandbox [NAME=value...] CMD [ARGS...]
# The one gateway to everything that is not the test's own bash. The environment is
# built here from nothing; extra NAME=value words go through to the command.
#
# stdin is part of the environment. A command gets the test's stdin only when that is
# a pipe or a file (a heredoc, a here-string, `run cmd <<<...`); a terminal or a
# socket becomes /dev/null. This is not tidiness: bash started with `-c` and a socket
# on stdin takes itself for a remote shell and skips $BASH_ENV, which agent harnesses
# (and some CI wrappers) hand to bats.
in_sandbox() {
  [ -n "${SANDBOX:-}" ] || { echo "in_sandbox: sandbox_init has not run" >&2; return 99; }
  case $HOME in "$SANDBOX"/*) ;; *) echo "in_sandbox: HOME is outside the sandbox: $HOME" >&2; return 99 ;; esac
  local black_hole=http://127.0.0.1:9
  local -a sandbox_env=(
    HOME="$HOME" PATH="$SANDBOX_PATH" TMPDIR="$SANDBOX/tmp" TMPPREFIX="$SANDBOX/tmp/zsh"
    LANG=en_US.UTF-8 TERM=dumb NO_COLOR=1
    STUB_STATE="$STUB_STATE" STUB_HOME="$BATS_TEST_DIRNAME/stubs"
    GIT_CONFIG_GLOBAL="${SUITE_GITCONFIG:-$HOME/.gitconfig}" GIT_CONFIG_NOSYSTEM=1
    GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0
    HTTP_PROXY="$black_hole" HTTPS_PROXY="$black_hole" ALL_PROXY="$black_hole"
    http_proxy="$black_hole" https_proxy="$black_hole" all_proxy="$black_hole"
  )
  # NAME=value words in front of the command join the environment, ahead of the confinement.
  while [[ ${1-} == [A-Za-z_]*=* ]]; do sandbox_env+=("$1"); shift; done
  local -a confine=()
  [ -z "${SUITE_PROFILE:-}" ] || confine=(
    /usr/bin/sandbox-exec -D "ROOT=$SANDBOX" -D "REAL_HOME=$SUITE_REAL_HOME" -D "REPO=$REPO_ROOT"
    -f "$SUITE_PROFILE")
  if [ -p /dev/stdin ] || [ -f /dev/stdin ]; then
    env -i "${sandbox_env[@]}" "${confine[@]}" "$@"
  else
    env -i "${sandbox_env[@]}" "${confine[@]}" "$@" </dev/null
  fi
}

# hide TOOL...: the named tools are not installed for the rest of this test.
hide() {
  local tool
  if [ ! -d "$SANDBOX/path" ]; then
    mkdir "$SANDBOX/path"
    ln -s "$SUITE_TOOLS"/* "$SANDBOX/path/"
    SANDBOX_PATH=$HOME/.local/bin:$SANDBOX/path
  fi
  for tool in "$@"; do rm -f "$SANDBOX/path/$tool"; done
}

# They run from the golden home, which no test modifies, so a test may delete or chmod
# the copy in its own HOME (the one launchd or the updater would run) without
# taking the script it is testing with it.
claude-rc()       { in_sandbox "$SUITE_HOME/.local/bin/claude-rc" "$@"; }
gh-repo-profile() { in_sandbox "$SUITE_HOME/.local/bin/gh-repo-profile" "$@"; }
brewfile-sync()   { in_sandbox "$SUITE_HOME/.local/bin/brewfile-sync" "$@"; }
statusline()      { in_sandbox "$SUITE_HOME/.claude/statusline.sh" "$@"; }

# stub TOOL VERB [ARGS...]: stdin passes through. Every stub answers `calls`, `sent`
# and `fail`; the rest of the verbs are listed at the top of each file in stubs/.
stub() {
  local tool=$1; shift
  in_sandbox STUB_CTL=1 "$SUITE_TOOLS/$tool" "$@"
}

# chezmoi_source [DIR]
# Makes DIR (default: this repo) the sandbox's chezmoi source, at the place chezmoi
# looks by default, ~/.local/share/chezmoi, as on a real machine. Nothing in the
# tests passes --source, so every chezmoi call, and every script that asks chezmoi
# where the source is, agrees.
chezmoi_source() {
  mkdir -p "$HOME/.local/share"
  ln -sfn "${1:-$REPO_ROOT}" "$HOME/.local/share/chezmoi"
}

# chezmoi_config [source=DIR] [email=ADDRESS] [machineType=work|personal]
# The state of a machine whose `chezmoi init` has been answered: the source, and the
# config file init would have written. Defaults: this repo, test@dotfiles.test,
# personal. (To exercise init itself, call chezmoi_source and run `chezmoi init`.)
# shellcheck disable=SC2120 # every argument is optional
chezmoi_config() {
  local source=$REPO_ROOT email=test@dotfiles.test machine=personal kv
  for kv in "$@"; do
    case $kv in
      source=*)      source=${kv#source=} ;;
      email=*)       email=${kv#email=} ;;
      machineType=*) machine=${kv#machineType=} ;;
      *) echo "chezmoi_config: unknown argument $kv" >&2; return 2 ;;
    esac
  done
  chezmoi_source "$source"
  mkdir -p "$HOME/.config/chezmoi"
  printf '[data]\n  email = "%s"\n  machineType = "%s"\n' "$email" "$machine" \
    >"$HOME/.config/chezmoi/chezmoi.toml"
}

# chezmoi_apply [chezmoi apply args...]
# The only way tests run `chezmoi apply`, and it never runs externals (a network
# clone) or scripts (they act on the machine).
chezmoi_apply() {
  in_sandbox chezmoi apply --no-tty --force --no-pager --color=false \
    --exclude externals,scripts --parent-dirs "$@"
}

# render TEMPLATE [chezmoi execute-template flags]: what chezmoi writes for a source
# file of this repo, given the current chezmoi_config.
render() {
  local template=$1; shift
  in_sandbox chezmoi execute-template "$@" <"$REPO_ROOT/$template"
}

# real_tool NAME: where the real tool lives. The system directories come first, so
# bash is macOS's 3.2 and git is Apple's whatever the caller's PATH says. Skipped: mise
# shims (a shim needs the caller's real HOME) and anything under the real HOME (the
# fence below closes it, so a tool installed only there could never run).
real_tool() {
  local dir IFS=:
  for dir in /bin /usr/bin /usr/sbin /sbin $PATH; do
    case $dir in */shims|*/shims/*|"$SUITE_REAL_HOME"|"$SUITE_REAL_HOME"/*) continue ;; esac
    if [ -x "$dir/$1" ] && [ ! -d "$dir/$1" ]; then printf '%s\n' "$dir/$1"; return 0; fi
  done
  return 1
}

# suite_build SUITE_DIR REAL_HOME
# Exports SUITE_TOOLS (the directory every sandbox PATH ends with), SUITE_HOME (the
# golden home each sandbox starts as a copy of) and SUITE_PROFILE (the seatbelt
# profile), all under SUITE_DIR. REAL_HOME is the caller's, captured before anything
# replaces it, so the profile can fence it off.
suite_build() {
  local suite=$1 name path stub tools=$1/tools golden=$1/golden-home
  # Resolved: the kernel matches the profile's paths after symlinks, so /var or a
  # symlinked home written the short way would silently fence nothing.
  export SUITE_REAL_HOME
  SUITE_REAL_HOME=$(cd "$2" && pwd -P)

  # The fence first, and proven before anything relies on it: the profile must apply on
  # this machine and must actually deny the real HOME. A fence that fails open fails
  # the run. The rest of the build runs behind it too.
  suite_write_profile "$suite/sandbox.sb"
  export SUITE_PROFILE=$suite/sandbox.sb
  local fence=(/usr/bin/sandbox-exec -D ROOT=/nonexistent -D REAL_HOME="$SUITE_REAL_HOME" -D REPO="$REPO_ROOT" -f "$SUITE_PROFILE")
  "${fence[@]}" /usr/bin/true ||
    { echo "setup_suite: sandbox-exec cannot apply the profile on this machine" >&2; return 1; }
  if "${fence[@]}" /usr/bin/stat "$SUITE_REAL_HOME" >/dev/null 2>&1; then
    echo "setup_suite: the seatbelt profile does not fence $SUITE_REAL_HOME; refusing to run" >&2
    return 1
  fi

  mkdir -p "$tools"
  for name in "${suite_real_tools[@]}"; do
    path=$(real_tool "$name") || { echo "setup_suite: no $name on this machine outside $SUITE_REAL_HOME" >&2; return 1; }
    ln -s "$path" "$tools/$name"
  done
  # Every executable in stubs/ is a stub. Adding one is adding a file.
  for stub in "$BATS_TEST_DIRNAME"/stubs/*; do
    [ "${stub##*/}" = stub.sh ] || ln -sf "$stub" "$tools/${stub##*/}"
  done
  export SUITE_TOOLS=$tools

  # The golden home is what `chezmoi apply` makes of the installed scripts, so their
  # installed names and modes (executable_, private_) are chezmoi's own, not a copy
  # of its rules. The build sandbox's own HOME keeps chezmoi's state out of it.
  unset SUITE_HOME
  sandbox_init "$suite"
  chezmoi_config
  mkdir -p "$golden"
  chezmoi_apply --destination "$golden" \
    "$golden/.local/bin" "$golden/.claude/statusline.sh" "$golden/.claude/shell-env.sh"
  ln -s "$tools/claude" "$golden/.local/bin/claude"
  # Outside any test's HOME on purpose: applying this repo's own ~/.gitconfig must not
  # replace the identity the fixtures commit with (the real one signs through 1Password).
  cat >"$suite/gitconfig" <<'GITCONFIG'
[user]
	name = Test User
	email = test@dotfiles.test
[init]
	defaultBranch = main
[commit]
	gpgsign = false
[protocol "file"]
	allow = always
[advice]
	detachedHead = false
GITCONFIG
  export SUITE_HOME=$golden SUITE_GITCONFIG=$suite/gitconfig
}

# suite_write_profile FILE: the seatbelt profile every in_sandbox command runs under.
# Parameters, set per command: ROOT (the test's sandbox), REAL_HOME, REPO.
suite_write_profile() {
  cat >"$1" <<'PROFILE'
(version 1)
(allow default)

;; Nothing a test runs writes anywhere but its own sandbox.
(deny file-write*)
(allow file-write*
  (subpath (param "ROOT"))
  (literal "/dev/null") (literal "/dev/dtracehelper"))

;; The real home is closed, whatever path a script builds to reach it. The repo under
;; test is the one thing in it a script may read.
(deny file-read* file-write* (subpath (param "REAL_HOME")))
(allow file-read* (subpath (param "REPO")))

;; The tool that changes the real machine cannot be executed, by any path.
(deny process-exec (literal "/bin/launchctl") (literal "/usr/bin/launchctl"))

;; Nothing here needs the network, so nothing has it.
(deny network*)
PROFILE
}
