#!/bin/bash
# start_watcher: one detached watch-client per (client pid, iTerm session).

# start_watcher <client_pid> <session_id> <tty>
start_watcher() {
  local marker="$HERDR_PLUGIN_STATE_DIR/watch-$1-$2" existing script
  existing="$(cat "$marker" 2>/dev/null || true)"
  if [[ -n "$existing" ]] && kill -0 "$existing" 2>/dev/null; then
    return 0
  fi
  script="$(cat "$HERDR_PLUGIN_ROOT/bin/watch-client.sh")"
  # Values travel as positional args, never spliced into the script text.
  nohup /bin/bash -c "$script" watch-client "$1" "$2" "$3" </dev/null >/dev/null 2>&1 &
  echo "$!" > "$marker"
}
