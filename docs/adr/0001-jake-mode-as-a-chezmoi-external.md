# jake-mode is a chezmoi external, wired by its own bin/link

Every machine gets jake-mode by declaring it in `.chezmoiexternal.toml` as a git-repo
external at `~/dev/jake-mode`, pulled at most hourly with `--ff-only`. A `run_after_`
script then runs jake-mode's `bin/link --prune`. jake-mode is where every skill of my own
lives, so tracking `main` automatically is what we want. Linking stays in `bin/link` so jake-mode
remains the one place that knows how its skills and rules flatten into a harness.

## Considered Options

- **chezmoi-managed symlinks** (`symlink_` entries per skill): rejected. They duplicate
  `bin/link`'s logic and go stale whenever a skill is added or renamed in jake-mode.
- **A hand-run clone step in the README**: rejected. It is one more thing a new machine
  forgets, and it never keeps existing machines current.
- **A run script that clones, pulls, and only warns when the pull fails**: rejected in
  favour of the declared external, accepting the consequence below.

## Consequences

A failed pull fails the whole `chezmoi apply`, not just jake-mode. That happens when
`~/dev/jake-mode` has diverged, is on a branch with no upstream, or has uncommitted edits
the pull would overwrite. jake-mode's own
conventions keep its main checkout clean on `main` (work happens in worktrees), so this
should be rare, and when it happens it is loud rather than silent.

The clone is pinned to HTTPS with a repo-local `insteadOf`, because the rendered
`.gitconfig` rewrites GitHub HTTPS URLs to SSH and lands before the clone on a new machine,
when no SSH keys exist yet.
