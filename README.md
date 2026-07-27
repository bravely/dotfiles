# dotfiles

Managed with [chezmoi](https://chezmoi.io). Source of truth lives here; `chezmoi apply`
renders it into `$HOME`.

## New machine

```sh
brew install chezmoi
chezmoi init --apply --ssh bravely/dotfiles
```

`init` prompts for the one machine-specific value (your email address, used for
`user.email` and as the principal in `~/.config/git/allowed_signers`) and writes it to
`~/.config/chezmoi/chezmoi.toml`. `--apply` then renders everything in one pass.

Without that config, the first apply fails with `map has no entry for key "email"` — the
`.chezmoi.toml.tmpl` in this repo exists to prevent exactly that.

Bootstrapping before SSH keys are available? The repo is public, so drop `--ssh` to clone
over HTTPS, then repoint the remote once 1Password is set up.

## Afterwards

```sh
brew bundle --file=~/Brewfile   # packages, casks, and Mac App Store apps
```

Commit signing expects the 1Password desktop app — `.gitconfig` points `gpg.ssh.program`
at its `op-ssh-sign`, and the SSH agent socket at `~/.1password/agent.sock`.

## Day to day

```sh
chezmoi diff      # what would change in $HOME
chezmoi apply     # apply it
chezmoi re-add    # pull edits made directly to a target file back into the source
```

Beware: `chezmoi apply` overwrites targets from the source, so installers that append to
`~/.zshrc` get erased. Run `chezmoi diff` after installing anything that edits dotfiles,
and fold what you want to keep back into the source.
