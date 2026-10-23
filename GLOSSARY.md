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
A skill of my own that has proven itself and lives in jake-mode.
_Avoid_: Stable skill, global skill

**Experimental skill**:
A skill of my own that is still being tried out and lives in this repo. It becomes a Promoted skill when it moves to jake-mode.
_Avoid_: Draft skill, local skill

**Wiring**:
Making a skill or rule visible to Claude Code by linking it from where it lives into the harness's own directories.
_Avoid_: Installing (that is what happens to a plugin)
