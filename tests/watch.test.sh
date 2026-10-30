#!/bin/bash
# bin/watch-client.sh and start_watcher: clear a tab once its herdr client is gone.

setup_watch_env() {
  mkdir -p "$TEST_TMP/bin" "$TEST_TMP/state"
  cat > "$TEST_TMP/bin/it2" <<'STUB'
#!/bin/bash
mkdir -p "$STUB_DIR/calls"
printf '%s\0' "$@" > "$STUB_DIR/calls/$$"
STUB
  # ps -t TTY lists what runs on a terminal; herdr-on-tty holds the pid of a re-attached client.
  cat > "$TEST_TMP/bin/ps" <<'STUB'
#!/bin/bash
if [[ "$1" == "-t" && -f "$STUB_DIR/herdr-on-tty" ]]; then
  p="$(cat "$STUB_DIR/herdr-on-tty")"
  kill -0 "$p" 2>/dev/null && echo "$p /opt/homebrew/bin/herdr"
fi
exit 0
STUB
  chmod +x "$TEST_TMP"/bin/*
  export STUB_DIR="$TEST_TMP" PS_BIN="$TEST_TMP/bin/ps" HERDR_ITERM_STATUS_IT2="$TEST_TMP/bin/it2"
  export HERDR_PLUGIN_ROOT="$ROOT" HERDR_PLUGIN_STATE_DIR="$TEST_TMP/state" WATCH_INTERVAL=0.2
}

calls_as_lines() {
  local f
  for f in "$TEST_TMP"/calls/*; do [[ -f "$f" ]] && tr '\0' '\n' < "$f"; done
  return 0
}

test_clears_after_client_exit() {
  setup_watch_env
  sleep 1 &
  local client=$!
  /bin/bash "$ROOT/bin/watch-client.sh" "$client" SESSION-1 /dev/ttys042
  assert_eq "$(printf 'session\nset-status\n--session=SESSION-1\n--status\n\n--dot-color\n\n--text-color\n')" \
    "$(calls_as_lines)" "one clear call for the session"
}

test_hands_over_to_reattached_client() {
  setup_watch_env
  sleep 0.3 &
  local first=$!
  sleep 1.5 &
  echo "$!" > "$TEST_TMP/herdr-on-tty"
  local start=$SECONDS
  /bin/bash "$ROOT/bin/watch-client.sh" "$first" SESSION-1 /dev/ttys042
  [[ $((SECONDS - start)) -ge 1 ]] || { echo "    cleared before the re-attached client left" >&2; return 1; }
  assert_eq "$(printf 'session\nset-status\n--session=SESSION-1\n--status\n\n--dot-color\n\n--text-color\n')" \
    "$(calls_as_lines)" "cleared once, after the second client exits"
}

test_single_watcher_per_client() {
  setup_watch_env
  load_lib common
  load_lib watch
  sleep 30 &
  local client=$! first second third
  start_watcher "$client" SESSION-1 /dev/ttys042
  first="$(cat "$TEST_TMP/state/watch-$client-SESSION-1")"
  start_watcher "$client" SESSION-1 /dev/ttys042
  start_watcher "$client" SESSION-1 /dev/ttys042
  second="$(cat "$TEST_TMP/state/watch-$client-SESSION-1")"
  third="$(pgrep -f "watch-client $client SESSION-1" | wc -l | tr -d ' ')"
  kill "$client" "$first" 2>/dev/null || true
  wait "$client" "$first" 2>/dev/null || true
  assert_eq "$first" "$second" "same watcher reused"
  assert_eq 1 "$third" "exactly one watcher process"
}
