# Sourced by non-interactive bash via $BASH_ENV (set in ~/.claude/settings.json).
# Hook scripts and tool-spawned shells read no startup file otherwise, so
# mise-managed tools (mix, elixir, node, …) are invisible to them: `mise activate`
# installs a precmd hook, and without a prompt that hook never fires.
# Shims resolve tools without needing activation.
case ":$PATH:" in
  *":$HOME/.local/share/mise/shims:"*) ;;
  *) export PATH="$HOME/.local/share/mise/shims:$PATH" ;;
esac
