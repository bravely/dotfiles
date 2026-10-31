# Dotfiles

The setup every machine of mine gets: shell, apps, git, and the Claude Code harness. This repo is the source of truth; a machine is whatever it renders.

## Claude Code

**Declared plugin**:
A Claude Code plugin enabled in this repo's Claude settings, so every machine set up from the repo gets it.
_Avoid_: Installed plugin (a plugin can be installed on one machine without being declared)

**Plugin skill**:
A skill that arrives through a Declared plugin, written and maintained by someone else.
_Avoid_: Third-party skill

**Promoted skill**:
A skill of my own that has proven itself. Like every skill of my own, it lives in jake-mode.
_Avoid_: Stable skill, global skill

**Experimental skill**:
A skill of my own that is still being tried out, which a metadata field on the skill says. It lives in jake-mode beside the Promoted skills and reaches the same places they do; it becomes a Promoted skill when that field comes off.
_Avoid_: Draft skill, local skill

**Reach**:
Where a skill of mine can be used. A skill with reach `all` is uploaded to my Claude account, so it works in chat, on mobile, and in every kind of Claude Code session. A skill with reach `code` works only in Claude Code sessions, local or cloud. A skill is `code` unless its metadata field says otherwise.
_Avoid_: Scope, surface (a surface is one place Claude runs, not a setting of the skill)

**Wiring**:
Making a skill or rule visible to Claude Code by linking it from where it lives into the harness's own directories.
_Avoid_: Installing (that is what happens to a plugin)
