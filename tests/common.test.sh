#!/bin/bash
# lib/common.sh: run_it2 passes argv through and never stalls its caller.
# shellcheck disable=SC2034 # IT2 and RUN_IT2_TIMEOUT are read by lib/common.sh

test_run_it2_in_command_substitution_returns_promptly() {
  load_lib common
  IT2=/bin/echo
  local start out
  start=$SECONDS
  out="$(run_it2 session list)"
  assert_eq "session list" "$out" "output passed through"
  # The timeout guard must not hold the $(...) pipe open for its full 5 seconds.
  [[ $((SECONDS - start)) -lt 2 ]] || { echo "    took $((SECONDS - start))s" >&2; return 1; }
}

test_run_it2_kills_a_hung_it2() {
  load_lib common
  RUN_IT2_TIMEOUT=1
  IT2=/bin/sleep
  local start=$SECONDS
  run_it2 30 || true
  [[ $((SECONDS - start)) -lt 4 ]] || { echo "    hung it2 not killed" >&2; return 1; }
}
