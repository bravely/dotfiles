# dotfiles

Managed with [chezmoi](https://chezmoi.io). Source of truth lives here; `chezmoi apply`
renders it into `$HOME`.

## New machine

In order. Each step depends on the ones before it.

1. **Sign in to the App Store.** `brew bundle` installs Mac App Store apps through
   `mas`, which can't sign in for you.

2. **Install Homebrew**, then put it on `PATH` for this shell. The rendered `.zshrc`
   does that for later shells. The installer also installs the Xcode command line
   tools (git, compilers) if they're missing.

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

3. **Install oh-my-zsh and its one third-party plugin** *before* chezmoi. Running the
   installer after chezmoi fails, because chezmoi has already created `~/.oh-my-zsh/custom`.
   `--keep-zshrc` stops it writing a `.zshrc` that chezmoi would then overwrite.

   ```sh
   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
   git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
   ```

4. **Install mise.** It isn't in the Brewfile. It installs to `~/.local/bin/mise`, which
   the oh-my-zsh `mise` plugin activates.

   ```sh
   curl https://mise.run | sh
   ```

5. **Apply the dotfiles.** No SSH keys exist yet, so clone over HTTPS (the repo is public):

   ```sh
   brew install chezmoi
   chezmoi init --apply bravely/dotfiles
   ```

   `init` asks two questions and writes the answers to `~/.config/chezmoi/chezmoi.toml`:

   - **Email address**: used for `user.email` and as the principal in
     `~/.config/git/allowed_signers`.
   - **Work or personal machine**: personal machines also get `Brewfile.personal`,
     work machines `Brewfile.work`.

   `--apply` then renders everything in one pass. Without that config, the first apply
   fails with `map has no entry for key "email"`. The `.chezmoi.toml.tmpl` in this repo
   exists to prevent that.

6. **Install everything else** (formulae, casks, Mac App Store apps):

   ```sh
   brew bundle --file=~/Brewfile
   ```

7. **Set up 1Password.** Sign in to the desktop app and turn on its SSH agent
   (Settings → Developer). Commit signing depends on it: `.gitconfig` points
   `gpg.ssh.program` at its `op-ssh-sign`, and `.zshrc` points `SSH_AUTH_SOCK` at
   `~/.1password/agent.sock`.

8. **Switch the dotfiles remote to SSH** now that keys are available, and log in to `gh`:

   ```sh
   chezmoi git -- remote set-url origin git@github.com:bravely/dotfiles.git
   gh auth login
   ```

9. **Grant permissions** when macOS asks: Karabiner-Elements needs Input Monitoring
   and its driver extension approved under Privacy & Security.

10. **Open a new terminal** so the rendered `.zshrc` loads, then run `chezmoi diff`. It
    should print nothing.

Not covered here: mise's own tool config (`~/.config/mise/config.toml`) isn't in this
repo, so install runtimes with `mise use -g` as you need them.

## Day to day

```sh
chezmoi diff      # what would change in $HOME
chezmoi apply     # apply it
chezmoi re-add    # pull edits made directly to a target file back into the source
```

Beware: `chezmoi apply` overwrites targets from the source, so installers that append to
`~/.zshrc` get erased. Run `chezmoi diff` after installing anything that edits dotfiles,
and fold what you want to keep back into the source.

## Scripts

`~/.local/bin/gh-repo-profile` applies my standard GitHub repo settings profile —
squash-only merges with auto-merge on, no wiki, Dependabot alerts on, and a "Safe
Main" ruleset that makes the default branch PR-only, signed, linear and CI-gated with
no bypass for anyone, admins included.

```sh
gh-repo-profile OWNER/REPO            # apply it
gh-repo-profile --dry-run OWNER/REPO  # show what would change
gh-repo-profile --help                # flags, and what is deliberately out of scope
```

It is idempotent, so re-running it updates in place rather than failing on the
existing ruleset. The profile came from auditing every non-default setting on one of
my own repos.

Two sharp edges the ruleset creates, both with an escape hatch:

- The required status check defaults to `ci`, which is a check *context* — for an
  ordinary workflow job, its job id. A repo with no job by that id can never merge to
  its default branch. The script warns when it can't find one; `--ci-check NAME` and
  `--no-status-check` change or drop it.
- Signed commits are required with no bypass, so an agent that commits unsigned gets
  stuck until the commits are re-signed. `--no-signatures` drops that rule.

Settings only. Workflow files, `.github/dependabot.yml` and labels are repo content
rather than settings, and are not copied.
