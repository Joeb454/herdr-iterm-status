#!/bin/bash
# Shared paths, and the timeout every external call runs under.

IT2="${HERDR_ITERM_STATUS_IT2:-/Applications/iTerm.app/Contents/Resources/utilities/it2}"

# run_with_timeout <seconds> <cmd> <args...>: macOS has no timeout(1), so a guard kills it.
# A wedged iTerm or herdr must not hold the lock or pile up hook processes.
run_with_timeout() {
  local secs=$1
  shift
  "$@" </dev/null &
  local pid=$!
  # The guard's fds are closed: inherited, they'd hold a caller's $(...) open until it fires.
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
  local guard=$!
  # Both waits tolerate failure (callers run under set -e) and hide the shell's "Terminated" report.
  local rc=0
  wait "$pid" 2>/dev/null || rc=$?
  kill "$guard" 2>/dev/null || true
  wait "$guard" 2>/dev/null || true
  return "$rc"
}

# run_it2 <args...>: argv passed straight through; never a shell string.
run_it2() {
  run_with_timeout "${RUN_IT2_TIMEOUT:-5}" "$IT2" "$@"
}
