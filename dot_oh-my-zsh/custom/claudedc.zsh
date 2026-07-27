# Open a directory in the Claude Code desktop app.
# Supports macOS, WSL2 on Windows 11 (launches the Windows app), and plain Linux.

_claude_urlenc() {
  emulate -L zsh
  setopt localoptions nomultibyte      # index bytes, so non-ASCII encodes as UTF-8
  local str="$1" out="" i c
  for (( i = 1; i <= ${#str}; i++ )); do
    c="${str[i]}"
    case "$c" in
      ([A-Za-z0-9._~-]) out+="$c" ;;
      (*) out+="$(printf '%%%02X' "'$c")" ;;
    esac
  done
  print -r -- "$out"
}

_claude_is_wsl() {
  [[ -n "$WSL_DISTRO_NAME" || -n "$WSL_INTEROP" ]] && return 0
  [[ -r /proc/sys/kernel/osrelease ]] && [[ "$(</proc/sys/kernel/osrelease)" == *[Mm]icrosoft* ]]
}

# Hand a claude:// URL to the OS so it reaches the registered protocol handler.
_claude_open_url() {
  emulate -L zsh
  local url="$1"

  if [[ "$OSTYPE" == darwin* ]]; then
    open "$url"
    return
  fi

  if _claude_is_wsl; then
    # Interop puts these on PATH; fall back to absolute paths if appendWindowsPath is off.
    local explorer="${commands[explorer.exe]:-/mnt/c/Windows/explorer.exe}"
    local pwsh="${commands[powershell.exe]:-/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe}"

    if (( $+commands[wslview] )); then
      wslview "$url"
    elif [[ -x "$explorer" ]]; then
      # explorer.exe exits 1 even on success, so don't propagate its status
      "$explorer" "$url" 2>/dev/null
      return 0
    elif [[ -x "$pwsh" ]]; then
      "$pwsh" -NoProfile -NonInteractive -Command "Start-Process '${url//\'/\'\'}'"
    else
      print -u2 "claudedc: no Windows launcher found (need wslview, explorer.exe or powershell.exe)"
      print -u2 "claudedc: is WSL interop enabled for this distro?"
      return 1
    fi
    return
  fi

  if (( $+commands[xdg-open] )); then
    xdg-open "$url" >/dev/null 2>&1
    return
  fi

  print -u2 "claudedc: don't know how to open a URL on this platform ($OSTYPE)"
  return 1
}

claudedc() {
  emulate -L zsh
  local dir="${1:-.}"
  dir="${dir:A}"                       # resolve to absolute path
  [[ -d "$dir" ]] || { print -u2 "claudedc: no such directory: $dir"; return 1; }

  # The Windows app can't read a Linux path, so translate it (\\wsl.localhost\...
  # for WSL-native dirs, C:\... under /mnt/c). Set CLAUDEDC_WSL_PATH_STYLE=linux
  # to pass the path through untranslated.
  local folder="$dir"
  if _claude_is_wsl && [[ "${CLAUDEDC_WSL_PATH_STYLE:-windows}" == windows ]]; then
    local win
    if win="$(wslpath -w -- "$dir" 2>/dev/null)" && [[ -n "$win" ]]; then
      folder="$win"
    else
      print -u2 "claudedc: wslpath failed, passing the Linux path through: $dir"
    fi
  fi

  local url
  url="claude://code/new?folder=$(_claude_urlenc "$folder")"
  (( $# > 1 )) && url+="&q=$(_claude_urlenc "${*:2}")"   # optional prefilled prompt

  _claude_open_url "$url"
}
