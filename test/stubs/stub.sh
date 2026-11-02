# Shared by every stub in this directory; not itself a stub, so setup_suite.bash
# skips it when it links the stubs into the tools directory.
#
# A stub is a bash script that sources this file, defines two functions, and ends
# with `stub_main TOOL "$@"`:
#
#   behave ARGS...    what the faked tool does for one call: stdout, stderr, exit
#                     status. Calls it does not model go to `stub_unexpected`.
#   ctl VERB ARGS...  the verbs a test can send with `stub TOOL VERB ARGS...`, to
#                     configure the stub's world or read back its state.
#
# Every stub also answers three verbs, implemented here:
#
#   calls                         every call so far, one per line, args shell-quoted
#   sent [N]                      stdin the stub captured (the last capture, or the Nth)
#   fail PREFIX [STATUS] [MSG]    calls whose recorded line starts with PREFIX exit
#                                 STATUS (default 1), print MSG to stderr, and do
#                                 nothing else
#
# State lives under $STUB_STATE/<tool>/ and nowhere else. Only this directory and the
# stub that owns a subdirectory know its layout; tests go through `stub`.
#
# Fail closed: outside a sandbox (no $STUB_STATE) a stub refuses to run, and a call
# a stub does not model exits 99 with a message, recorded in $STUB_STATE/unexpected
# for the test's teardown to report.

stub_main() {
  local tool=$1; shift
  STUB_TOOL=$tool
  if [ -z "${STUB_STATE:-}" ] || [ ! -d "$STUB_STATE" ]; then
    echo "stub $tool: no sandbox (STUB_STATE is unset); refusing to run" >&2
    exit 99
  fi
  STUB_DIR=$STUB_STATE/$tool
  [ -d "$STUB_DIR" ] || mkdir -p "$STUB_DIR"

  if [ -n "${STUB_CTL:-}" ]; then
    stub_control "$@"
    exit $?
  fi

  stub_line "$@"
  printf '%s\n' "$STUB_LINE" >>"$STUB_DIR/calls"
  stub_injected_failure && exit "$STUB_FAIL_STATUS"
  behave "$@"
  exit $?
}

# STUB_LINE: the call as one readable line. Plain words stay bare, anything awkward
# is quoted, so a test can compare against what it would have typed.
stub_line() {
  local arg out=
  for arg in "$@"; do
    printf -v arg '%q' "$arg"
    out="$out${out:+ }$arg"
  done
  STUB_LINE=$out
}

# True (and sets STUB_FAIL_STATUS) when a `fail` rule matches the current call.
stub_injected_failure() {
  local status message prefix
  [ -f "$STUB_DIR/fail" ] || return 1
  while IFS=$'\037' read -r status message prefix; do
    case $STUB_LINE in
      "$prefix"*)
        [ -z "$message" ] || echo "$message" >&2
        STUB_FAIL_STATUS=$status
        return 0 ;;
    esac
  done <"$STUB_DIR/fail"
  return 1
}

# Saves this call's stdin so a test can read what was sent (a request body, say).
stub_capture_stdin() {
  local n
  n=$(cat "$STUB_DIR/captures" 2>/dev/null || echo 0)
  n=$((n + 1))
  cat >"$STUB_DIR/stdin.$n"
  echo "$n" >"$STUB_DIR/captures"
}

stub_unexpected() {
  stub_line "$@"
  echo "stub $STUB_TOOL: unexpected call: $STUB_LINE" >&2
  echo "$STUB_TOOL $STUB_LINE" >>"$STUB_STATE/unexpected"
  exit 99
}

stub_control() {
  local verb=${1-}
  shift || true
  case $verb in
    calls) cat "$STUB_DIR/calls" 2>/dev/null || true ;;
    sent)
      local n=${1:-$(cat "$STUB_DIR/captures" 2>/dev/null || echo 0)}
      cat "$STUB_DIR/stdin.$n" ;;
    fail)
      printf '%s\037%s\037%s\n' "${2:-1}" "${3-}" "${1:?fail needs a call prefix}" >>"$STUB_DIR/fail" ;;
    *) ctl "$verb" "$@" ;;
  esac
}

# Default for a stub with no verbs of its own.
ctl() {
  echo "stub $STUB_TOOL: unknown verb: $1" >&2
  return 2
}
