#!/usr/bin/env bats
#
# Invariants of the repository that keep the rest of the suite honest. None of these
# test a script's behaviour; each fails when a change would quietly make the suite
# cover less than it claims.

load harness

# The installed scripts, as targets relative to HOME, from chezmoi's own view of the
# repo: anything it puts in ~/.local/bin, and any .sh file.
installed_scripts() {
  chezmoi_config
  in_sandbox chezmoi managed --include=files --path-style=relative |
    grep -E '^\.local/bin/|\.sh$'
}

# bats runs on whatever bash is first on PATH, and on a stock Mac that is bash 3.2,
# where a failing [[ ]] that is not a test's last command is ignored. A bare `! cmd`
# is ignored on every bash. Either way the test passes without checking anything.
unguarded_assertions() {
  grep -nE '^[[:space:]]*(\[\[|!)[[:space:]]' "$BATS_TEST_DIRNAME"/*.bats "$BATS_TEST_DIRNAME"/*.bash |
    grep -v '|| false$' || true
}

@test "every [[ ]] or ! assertion ends in || false, so no bash can skip it" {
  run unguarded_assertions
  [ -z "$output" ] || { sed 's/^/# /' <<<"$output" >&3; false; }
}

@test "every script chezmoi installs has a test file named after it" {
  missing=
  for target in $(installed_scripts); do
    name=$(basename "$target"); name=${name%.sh}
    [ -f "$BATS_TEST_DIRNAME/$name.bats" ] || missing="$missing $name"
  done
  [ -z "$missing" ] || { echo "no test file for:$missing" >&2; return 1; }
}

@test "every test file loads the harness, so it is sandboxed" {
  run grep -L '^load harness$' "$BATS_TEST_DIRNAME"/*.bats
  [ -z "$output" ]
}

@test "chezmoi does not install the tests or the CI configuration into HOME" {
  chezmoi_config
  run in_sandbox chezmoi managed --path-style=relative
  [ "$status" -eq 0 ]
  [[ $output != *test/* && $output != *.github* ]] || false
}

@test "the workflow's job id is the one gh-repo-profile requires by default" {
  stub gh route contents/.github/workflows <<<'[{"name": "test.yml"}]'
  stub gh route contents/.github/workflows/test.yml <"$REPO_ROOT/.github/workflows/test.yml"
  run gh-repo-profile --dry-run bravely/dotfiles
  [ "$status" -eq 0 ]
  [[ $output == *"'ci' matches a job id in .github/workflows/test.yml"* ]] || false
}
