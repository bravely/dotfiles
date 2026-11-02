# bats runs setup_suite once per `bats` invocation, before any test, and finds this
# file by name in the test directory (also for `bats test/one.bats`). Whatever it
# exports, every test in every file inherits, whether or not that file loads the
# harness. That is what makes it the backstop: a new test file that forgets
# `load harness` still starts with a throwaway HOME and none of the caller's
# startup-file variables, so it can't reach the real ones by accident.

setup_suite() {
  local suite real_home=$HOME
  suite=$(cd "$BATS_SUITE_TMPDIR" && pwd -P)

  # shellcheck source=harness.bash
  . "$BATS_TEST_DIRNAME/harness.bash"
  suite_build "$suite" "$real_home"

  # suite_build leaves HOME pointing at its own build sandbox. Replace that with the
  # guard HOME that stays for the whole run.
  export HOME=$suite/guard-home
  mkdir -p "$HOME"
  unset BASH_ENV ENV ZDOTDIR XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
  export GIT_CONFIG_GLOBAL=$HOME/.gitconfig GIT_CONFIG_NOSYSTEM=1
}
