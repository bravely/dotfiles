# Skills reach my Claude account by hand upload, gated in CI; cloud sessions wire the rest

A skill with reach `all` has to work in chat, on mobile, and in Claude Code cloud sessions,
and the only thing that reaches all three is a skill uploaded to my claude.ai account. That
upload has no API: the Skills API writes to a separate API-workspace store that claude.ai
and Claude Code never read. So I upload `all` skills by hand, and jake-mode's CI makes that
cheap and hard to forget. A required check on any PR touching an `all` skill builds the
upload zips, validates their frontmatter against what claude.ai accepts, and passes only
once the PR carries the `account-synced` label. Reach `code` skills and all rules reach
cloud sessions a different way: each cloud environment's setup script clones jake-mode and
runs its `bin/cloud-setup`, which wires them into the VM's `~/.claude` the same way
`bin/link` does on a Mac.

## Considered Options

- **Uploading through the Skills API from a GitHub Action**: rejected. The docs state
  plainly that skills uploaded through the API are not available on claude.ai, and Claude
  Code only syncs skills from the claude.ai account.
- **jake-mode as a plugin marketplace**: rejected. Cloud sessions do not install plugins,
  whether a repo's settings declare them or they come from my own settings, and plugins
  cannot carry rules. Attaching a custom marketplace to a personal claude.ai account is not
  documented.
- **Automating the claude.ai upload page with a browser agent or script**: rejected. The
  Consumer Terms forbid automated access except through an API key or where Anthropic
  explicitly permits it. Nothing permits this, and the risk falls on my personal account.
- **Committing my skills into every repo's `.claude/skills/`**: rejected. It copies them
  into every repo, and it still leaves chat and mobile without them.

## Consequences

- Skill frontmatter may only use the keys claude.ai accepts (`name`, `description`,
  `license`, `compatibility`, `metadata`, `allowed-tools`), so custom fields such as reach and
  experimental go under `metadata`.
- On a Mac, `bin/link` skips `all` skills, because the account sync already delivers them
  and linking them too would list each one twice. An edit to an `all` skill is not live
  locally until it is uploaded, unless I link it on purpose for a test.
- The upload comes from the PR before merging, so an abandoned PR can leave the account
  ahead of `main`.
- A cloud environment without the setup-script bootstrap gets only the `all` skills. The
  setup script's filesystem is cached for up to about a week, so a SessionStart hook pulls
  jake-mode and wires it again at the start of each session.
- Per-surface control does not exist for account skills. A skill wanted in chat is in
  every surface, which is why reach defaults to `code`.
