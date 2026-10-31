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

   `--apply` then renders everything in one pass. That includes cloning
   [jake-mode](https://github.com/bravely/jake-mode) to `~/dev/jake-mode` over HTTPS and
   linking its skills and rules into `~/.claude/`. Without that config, the first apply
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

8. **Switch the dotfiles and jake-mode remotes to SSH** now that keys are available, and
   log in to `gh`:

   ```sh
   chezmoi git -- remote set-url origin git@github.com:bravely/dotfiles.git
   git -C ~/dev/jake-mode remote set-url origin git@github.com:bravely/jake-mode.git
   gh auth login
   ```

9. **Grant permissions** when macOS asks: Karabiner-Elements needs Input Monitoring
   and its driver extension approved under Privacy & Security.

10. **Open a new terminal** so the rendered `.zshrc` loads, then run `chezmoi diff`. It
    should print nothing.

11. **Install Claude Code and let it fetch its plugins.** chezmoi has already written
    `~/.claude/settings.json`, which declares the plugins every machine gets. Claude Code
    installs them in the background during its first session, so launch it once, quit,
    and check:

    ```sh
    curl -fsSL https://claude.ai/install.sh | bash
    claude
    claude plugin list
    ```

    The list should show `mattpocock-skills@claude-plugins-official` and
    `pstack@cursor-plugins`. My own Promoted skills come from jake-mode, which step 5
    already cloned and wired; `ls -l ~/.claude/skills` should show links into
    `~/dev/jake-mode`. If one is missing, jake-mode's `wire-skills` skill has the
    troubleshooting order.

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

The same goes for Claude Code: `/plugin`, `/config` and `/model` write to the live
`~/.claude/settings.json`. To keep a plugin or setting on every machine, run
`chezmoi re-add ~/.claude/settings.json` and commit; otherwise the next apply reverts it.

`chezmoi apply` also keeps jake-mode current: at most once an hour it runs
`git pull --ff-only` in `~/dev/jake-mode`, then relinks its skills and rules, pruning links
to any that were removed. If that checkout has diverged from `origin`, is on a branch with
no upstream, or has uncommitted edits to files the pull would change, the pull fails and
so does the whole apply. Sort out jake-mode's main checkout and apply again. To pull now
instead of waiting out the hour: `chezmoi apply --refresh-externals`.

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

`~/.local/bin/claude-rc` keeps a `claude remote-control` server running for a repo,
so I can start sessions in it from claude.ai/code or the Claude mobile app while this
Mac is awake. Each server is a LaunchAgent that starts at login and is restarted if it
dies. The script writes the agents on demand rather than chezmoi writing them, because
which repos get one differs per machine and they often aren't cloned when chezmoi runs.

```sh
claude-rc ensure [DIR]           # set up or update the server for the repo at DIR (default: here); no-op if current
claude-rc status                 # every server and the updater, and what's wrong with each
claude-rc restart [DIR | --all]  # restart one server, or all of them
claude-rc remove [DIR]           # stop it and delete its LaunchAgent, even if the repo is gone
```

A worktree resolves to its main checkout, so running it from a session's worktree
sets up the repo itself; a submodule is served as itself. `ensure` rewrites and
reloads a server whose LaunchAgent differs from what the script writes now, so
rerunning it after the script changes picks the change up. Everything exits 1
when it couldn't do what was asked, so another session can rely on the status. Each remote session gets its own worktree
(`--spawn=worktree`) and runs in auto permission mode. The servers use whichever
Claude account this Mac is logged in to, so a work machine serves the work account.
Logs are in `~/Library/Logs/claude-rc-<path>.log`.

`ensure` also installs one updater agent per machine. It watches
`~/.local/bin/claude` and runs `claude-rc restart --all` when it changes, because
Claude's updater prunes old versions, and a server still running a pruned version
reports Ready while every session it starts fails.

A server has no terminal to answer prompts, so two one-time steps come first, and
`ensure` refuses until they're done:

1. Run `claude` in the repo and accept the folder-trust prompt.
2. Once per Mac, run `claude remote-control` in a terminal, answer `y`, wait for
   Ready, then Ctrl+C. That terminal run keeps the folder registered for a few
   minutes after it stops. A server started meanwhile fails with "already served
   by a terminal `claude remote-control`" and launchd retries it every minute
   until the registration expires. A server restarted by launchd doesn't hit this.

Each start registers a new environment rather than reusing the last one, so every
restart, including the updater's, leaves a grayed-out entry for that repo in the
Claude app. The live one is the one that isn't grayed out.
