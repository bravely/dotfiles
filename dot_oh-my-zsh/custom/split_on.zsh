split_on() {
  if [[ -z $2 ]]; then
    awk -F "$1" '{ for (i=1; i<=NF; i++) print $i }' | sort -f
  else
    awk -F "$1" '{ for (i=1; i<=NF; i++) print $i }' <<< "$2" | sort -f
  fi
}
