#!/bin/bash
# Shared paths and the single place it2 is executed.

IT2="${HERDR_ITERM_STATUS_IT2:-/Applications/iTerm.app/Contents/Resources/utilities/it2}"

# run_it2 <args...>: argv passed straight through; never a shell string.
# Killed after RUN_IT2_TIMEOUT seconds so a wedged iTerm can't pile up hook processes.
run_it2() {
  "$IT2" "$@" </dev/null &
  local pid=$!
  # The guard's fds are closed: inherited, they'd hold a caller's $(...) open until it fires.
  ( sleep "${RUN_IT2_TIMEOUT:-5}"; kill "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
  local guard=$!
  wait "$pid"
  local rc=$?
  kill "$guard" 2>/dev/null
  wait "$guard" 2>/dev/null
  return "$rc"
}
