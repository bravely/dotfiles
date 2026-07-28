gw() {
  emulate -L zsh
  setopt auto_pushd

  if [[ $1 == (-h|--help) ]]; then
    cat <<'EOF'
Usage: gw [branch]

Switch to an existing git worktree. Never creates one.

  gw            Interactive picker (fzf), pre-selects current worktree
  gw <branch>   Jump to that worktree; falls back to fuzzy match
  gw -h|--help  This message
EOF
    return 0
  fi

  git rev-parse --git-dir >/dev/null 2>&1 \
    || { print -u2 "gw: not a git repo"; return 1 }

  local line path b
  local -a wts
  while IFS= read -r line; do
    case $line in
      (worktree\ *) path=${line#worktree } ;;
      (branch\ *)   b=${line#branch }; b=${b#refs/heads/}
                    wts+=( "$b"$'\t'"$path" ) ;;
      (detached)    wts+=( "(detached)"$'\t'"$path" ) ;;
    esac
  done < <(git worktree list --porcelain)

  (( $#wts )) || { print -u2 "gw: no worktrees"; return 1 }
  wts=( "${(@oi)wts}" )

  local -a fzf_args=(
    --delimiter=$'\t' --with-nth=1 --layout=reverse --height=40%
    --preview='echo {2}' --preview-window=up:1
  )
  local dir sel

  if [[ -n $1 ]]; then
    dir=${${wts[(r)${(b)1}$'\t'*]}#*$'\t'}
    if [[ -z $dir ]]; then
      (( $+commands[fzf] )) || { print -u2 "gw: no worktree for '$1'"; return 1 }
      sel=$(fzf $fzf_args --select-1 --exit-0 --query=$1 <<< ${(F)wts})
      dir=${sel#*$'\t'}
    fi
    [[ -n $dir ]] || { print -u2 "gw: no worktree for '$1'"; return 1 }
  else
    (( $+commands[fzf] )) || { print -u2 "gw: fzf required for interactive mode"; return 1 }
    local top=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n $top ]]; then
      local pos=${wts[(i)*$'\t'${(b)top}]}
      (( pos <= $#wts )) && fzf_args+=( --bind="load:pos($pos)" )
    fi
    sel=$(fzf $fzf_args <<< ${(F)wts}) || return 1
    dir=${sel#*$'\t'}
  fi

  cd -- "$dir"
}

_gw() {
  local -a branches
  branches=( ${(f)"$(git worktree list --porcelain 2>/dev/null |
    awk '/^branch /{ sub(/^branch refs\/heads\//,""); print }')"} )
  (( $#branches )) && _describe -t worktrees 'worktree' branches
}
compdef _gw gw
