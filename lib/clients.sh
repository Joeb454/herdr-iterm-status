#!/bin/bash
# Map a herdr session to the iTerm tabs showing it.

PS_BIN="${PS_BIN:-/bin/ps}"

# client_pids_and_ttys <client_sock_path>
# stdin: `lsof -nP -U -c herdr` output. Prints "pid<TAB>/dev/ttyNNN" per client of that socket.
# The server's accepted connections are named after the socket; each client's end shows
# "->ADDR" with the same address, which is how a client is tied to one session's server.
client_pids_and_ttys() {
  local pid tty
  awk -v sock="$1" '
    NR == 1 { next }
    {
      # Unix sockets have no NODE value, so NAME is field 8 (the header suggests 9).
      name = $8
      for (i = 9; i <= NF; i++) name = name " " $i
      if (name == sock) { addr[$6] = 1; server[$2] = 1 }
      else if (substr(name, 1, 2) == "->") { peer[NR] = substr(name, 3); pid[NR] = $2 }
    }
    END {
      for (r in peer) if ((peer[r] in addr) && !(pid[r] in server) && !(pid[r] in seen)) {
        seen[pid[r]] = 1; print pid[r]
      }
    }' | sort -n | while read -r pid; do
      tty="$("$PS_BIN" -o tty= -p "$pid" 2>/dev/null | tr -d ' ')" || continue
      [[ -n "$tty" && "$tty" != "??" ]] && printf '%s\t/dev/%s\n' "$pid" "$tty"
    done
  return 0
}

# iterm_sessions_for_ttys <tty>...
# stdin: `it2 session list` output. Prints "session_id<TAB>tty" for each listed tty.
# Only the first (id) and last (tty) columns are used: tab names are free text.
iterm_sessions_for_ttys() {
  awk -F '\t' -v want="$*" '
    BEGIN { n = split(want, w, " "); for (i = 1; i <= n; i++) ok[w[i]] = 1 }
    { tty = $NF; gsub(/\\\//, "/", tty); if (tty in ok) printf "%s\t%s\n", $1, tty }'
}
