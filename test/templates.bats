#!/usr/bin/env bats
#
# Tests for the chezmoi templates: .chezmoi.toml.tmpl, Brewfile.tmpl, dot_gitconfig.tmpl,
# dot_config/git/allowed_signers.tmpl, dot_config/starship.toml.tmpl, dot_zshrc.tmpl and
# run_after_link-jake-mode.sh.tmpl. The real chezmoi renders them from this repo,
# for a work and a personal answer, inside the sandbox: its config, state and
# destination are all under the test's fake HOME, and externals and scripts never run
# (chezmoi_apply).

bats_require_minimum_version 1.5.0
load harness

# init_machine EMAIL work|personal: what answering the prompts on a new machine does.
# Prompts are answered by their text, which is how chezmoi takes them non-interactively.
init_machine() {
  chezmoi_source
  in_sandbox chezmoi init \
    --promptString "Email address=$1" \
    --promptChoice "Is this a work or personal machine=$2"
}

# A key of the data chezmoi has for this machine.
machine_data() { in_sandbox chezmoi data --format=json | jq -r ".$1"; }

# Brewfile entries (brew, cask, tap, ...) one per line, sorted, from files or stdin.
entries() { grep -hE '^[a-z]+ "' "$@" | sort -u; }

@test "init records the email and a work machine type" {
  init_machine jake@work.test work
  [ "$(machine_data email)" = jake@work.test ]
  [ "$(machine_data machineType)" = work ]
}

@test "init records a personal machine type" {
  init_machine jake@home.test personal
  [ "$(machine_data machineType)" = personal ]
}

@test "init on a configured machine keeps the answers it has instead of asking again" {
  init_machine jake@work.test work
  init_machine other@home.test personal
  [ "$(machine_data email)" = jake@work.test ]
  [ "$(machine_data machineType)" = work ]
}

@test "Brewfile: a work machine gets the common and work lists and nothing only the personal list has" {
  chezmoi_config machineType=work
  run render Brewfile.tmpl
  [ "$status" -eq 0 ]
  rendered=$(entries <<<"$output")
  [ -z "$(comm -23 <(entries "$REPO_ROOT"/.chezmoitemplates/Brewfile.common "$REPO_ROOT"/.chezmoitemplates/Brewfile.work) <(echo "$rendered"))" ]
  personal_only=$(comm -23 <(entries "$REPO_ROOT"/.chezmoitemplates/Brewfile.personal) <(entries "$REPO_ROOT"/.chezmoitemplates/Brewfile.common "$REPO_ROOT"/.chezmoitemplates/Brewfile.work))
  [ -z "$(comm -12 <(echo "$personal_only") <(echo "$rendered"))" ]
}

@test "Brewfile: a personal machine gets the common and personal lists and nothing only the work list has" {
  chezmoi_config machineType=personal
  run render Brewfile.tmpl
  [ "$status" -eq 0 ]
  rendered=$(entries <<<"$output")
  [ -z "$(comm -23 <(entries "$REPO_ROOT"/.chezmoitemplates/Brewfile.common "$REPO_ROOT"/.chezmoitemplates/Brewfile.personal) <(echo "$rendered"))" ]
  work_only=$(comm -23 <(entries "$REPO_ROOT"/.chezmoitemplates/Brewfile.work) <(entries "$REPO_ROOT"/.chezmoitemplates/Brewfile.common "$REPO_ROOT"/.chezmoitemplates/Brewfile.personal))
  [ -z "$(comm -12 <(echo "$work_only") <(echo "$rendered"))" ]
}

@test "gitconfig: git accepts it and it carries the machine's email, for both answers" {
  for machine in work personal; do
    chezmoi_config machineType=$machine email="jake@$machine.test"
    render dot_gitconfig.tmpl >"$HOME/rendered.gitconfig"
    run in_sandbox git config --file "$HOME/rendered.gitconfig" user.email
    [ "$status" -eq 0 ]
    [ "$output" = "jake@$machine.test" ]
  done
}

@test "gitconfig: signs with ssh keys checked against the allowed_signers file in this home" {
  chezmoi_config
  render dot_gitconfig.tmpl >"$HOME/rendered.gitconfig"
  run in_sandbox git config --file "$HOME/rendered.gitconfig" gpg.format
  [ "$output" = ssh ]
  run in_sandbox git config --file "$HOME/rendered.gitconfig" gpg.ssh.allowedSignersFile
  [ "$output" = "$HOME/.config/git/allowed_signers" ]
}

@test "allowed_signers: the key is trusted for the machine's email" {
  chezmoi_config email=jake@work.test
  run render dot_config/git/allowed_signers.tmpl
  [ "$status" -eq 0 ]
  [ "$(grep -v '^#' <<<"$output" | awk '{print $1, $2, $3}')" = 'jake@work.test namespaces="git" ssh-ed25519' ]
}

@test "zshrc: renders to valid zsh, for both answers" {
  for machine in work personal; do
    chezmoi_config machineType=$machine
    render dot_zshrc.tmpl >"$HOME/rendered.zshrc"
    run in_sandbox zsh -n "$HOME/rendered.zshrc"
    [ "$status" -eq 0 ]
  done
}

@test "zshrc: pnpm and bun live under the account's home" {
  chezmoi_config
  run render dot_zshrc.tmpl --override-data '{"chezmoi": {"username": "alice"}}'
  [[ $output == *'export PNPM_HOME="/Users/alice/Library/pnpm"'* ]] || false
  [[ $output == *'/Users/alice/.bun/_bun'* ]] || false
}

@test "zshrc: a mac gets nothing meant for Linux" {
  chezmoi_config
  run render dot_zshrc.tmpl
  [[ $output != *linuxbrew* ]] || false
}

@test "starship config: a mac gets the Rosetta indicator and Linux does not" {
  chezmoi_config
  run render dot_config/starship.toml.tmpl
  [[ $output == *"[custom.architecture]"* ]] || false
  run render dot_config/starship.toml.tmpl --override-data '{"chezmoi": {"os": "linux"}}'
  [[ $output != *"[custom.architecture]"* ]] || false
}

# A jake-mode checkout whose bin/link records its arguments and exits with $1.
fake_jake_mode() {
  mkdir -p "$HOME/dev/jake-mode/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"$HOME/link.args"\nexit %s\n' "${1:-0}" >"$HOME/dev/jake-mode/bin/link"
  chmod +x "$HOME/dev/jake-mode/bin/link"
}

@test "link script: links jake-mode's skills and rules into ~/.claude, pruning stale links" {
  chezmoi_config
  fake_jake_mode
  render run_after_link-jake-mode.sh.tmpl >"$HOME/run.sh"
  run in_sandbox sh "$HOME/run.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/link.args")" = "--prune
--skills-target
$HOME/.claude/skills
--rules-target
$HOME/.claude/rules" ]
}

@test "link script: fails when link fails, so the apply fails" {
  chezmoi_config
  fake_jake_mode 3
  render run_after_link-jake-mode.sh.tmpl >"$HOME/run.sh"
  run in_sandbox sh "$HOME/run.sh"
  [ "$status" -eq 3 ]
}

@test "link script: fails when jake-mode has not been cloned" {
  chezmoi_config
  render run_after_link-jake-mode.sh.tmpl >"$HOME/run.sh"
  run in_sandbox sh "$HOME/run.sh"
  [ "$status" -ne 0 ]
}

@test "a new work machine: init, then apply, writes the dotfiles and a second apply changes nothing" {
  init_machine jake@work.test work
  run chezmoi_apply
  [ "$status" -eq 0 ]
  for target in .zshrc .gitconfig Brewfile .config/git/allowed_signers .config/starship.toml; do
    [ -s "$HOME/$target" ]
  done
  [ -x "$HOME/.local/bin/claude-rc" ]
  run in_sandbox chezmoi verify --exclude externals,scripts
  [ "$status" -eq 0 ]
}

@test "a new personal machine: init, then apply, writes the dotfiles" {
  init_machine jake@home.test personal
  run chezmoi_apply
  [ "$status" -eq 0 ]
  [ -s "$HOME/Brewfile" ]
  run in_sandbox git config --file "$HOME/.gitconfig" user.email
  [ "$output" = jake@home.test ]
}
