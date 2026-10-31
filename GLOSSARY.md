# Dotfiles

The setup every machine of mine gets: shell, apps, git, and the Claude Code harness. This repo is the source of truth; a machine is whatever it renders.

## Claude Code

**Declared plugin**:
A Claude Code plugin enabled in this repo's Claude settings, so every machine set up from the repo gets it.
_Avoid_: Installed plugin (a plugin can be installed on one machine without being declared)

**Plugin skill**:
A skill that arrives through a Declared plugin, written and maintained by someone else.
_Avoid_: Third-party skill

**Skill of my own**:
A skill I wrote or ported myself. Every one lives in [jake-mode](https://github.com/bravely/jake-mode), whose `GLOSSARY.md` defines the terms for them: Promoted skill, Experimental skill, Reach, and Wiring.
_Avoid_: Local skill, custom skill
