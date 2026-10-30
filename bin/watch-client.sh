#!/bin/bash
# watch-client.sh <client_pid> <iterm_session_id> <tty>
# Clears the iTerm status once the herdr client on that tab exits (detach or quit), so a
# plain shell tab is never left showing agent state. Runs detached; start_watcher passes
# this file's text via `bash -c` so upgrading or removing the plugin can't break it mid-run.
set -uo pipefail

client="$1" session="$2" tty="$3"
IT2="${HERDR_ITERM_STATUS_IT2:-/Applications/iTerm.app/Contents/Resources/utilities/it2}"
PS_BIN="${PS_BIN:-/bin/ps}"

while [[ -n "$client" ]]; do
  while kill -0 "$client" 2>/dev/null; do
    sleep "${WATCH_INTERVAL:-3}"
  done
  # A quick re-attach puts a new herdr client on the same tab before any hook runs to
  # watch it, so keep watching that one rather than leave it unguarded.
  client="$("$PS_BIN" -t "${tty#/dev/}" -o pid=,comm= 2>/dev/null | awk '$2 ~ /herdr$/ { print $1; exit }')"
done

"$IT2" session set-status "--session=$session" --status "" --dot-color "" --text-color "" </dev/null >/dev/null 2>&1
