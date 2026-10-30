#!/bin/bash
# Shared paths and the single place it2 is executed.

IT2="${HERDR_ITERM_STATUS_IT2:-/Applications/iTerm.app/Contents/Resources/utilities/it2}"

# run_it2 <args...>: argv passed straight through; never a shell string.
# Killed after 5s so a wedged iTerm can't pile up hook processes.
run_it2() {
  "$IT2" "$@" </dev/null &
  local pid=$!
  ( sleep 5; kill "$pid" 2>/dev/null ) &
  local guard=$!
  wait "$pid"
  local rc=$?
  kill "$guard" 2>/dev/null
  wait "$guard" 2>/dev/null
  return "$rc"
}
