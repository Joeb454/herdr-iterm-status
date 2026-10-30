#!/bin/bash
# Setup checks for the iTerm status plugin, each failure with the exact fix.
set -uo pipefail

ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-}"
LSOF_BIN="${LSOF_BIN:-/usr/sbin/lsof}"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/clients.sh
source "$ROOT/lib/clients.sh"

failed=0
ok() { printf '✓ %s\n' "$1"; }
bad() { printf '✗ %s\n  → %s\n' "$1" "$2"; failed=1; }

if [[ -x "$IT2" ]]; then
  ok "iTerm2's it2 tool found"
else
  bad "it2 not found at $IT2" "Update iTerm2 to 3.7 or later (iTerm2 → Check for Updates)."
fi

if list="$(run_it2 session list 2>/dev/null)"; then
  ok "iTerm2 Python API is reachable"
else
  bad "Can't reach iTerm2's Python API" \
    "In iTerm2, open Settings → General → Magic and tick 'Enable Python API'. If iTerm asks whether to allow the connection, choose Allow."
  list=""
fi

sock="$(dirname "${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}")/herdr-client.sock"
clients="$("$LSOF_BIN" -nP -U -c herdr 2>/dev/null | client_pids_and_ttys "$sock")"
ttys=()
while IFS=$'\t' read -r _ tty; do [[ -n "$tty" ]] && ttys+=("$tty"); done <<< "$clients"
if [[ ${#ttys[@]} -gt 0 && -n "$(iterm_sessions_for_ttys "${ttys[@]}" <<< "$list")" ]]; then
  ok "This herdr session is open in an iTerm2 tab"
else
  bad "No iTerm2 tab is showing this herdr session" \
    "Attach to herdr from an iTerm2 tab; the status only appears on iTerm2 tabs."
fi

user="$CONFIG_DIR/config.json"
if [[ -z "$CONFIG_DIR" || ! -f "$user" ]]; then
  ok "Using default settings (no config.json)"
elif jq -e 'type == "object"' "$user" >/dev/null 2>&1; then
  ok "Settings file is valid: $user"
else
  bad "Settings file isn't valid JSON: $user" "Fix the JSON or delete the file to use the defaults."
fi

cat <<'NOTE'

Note: with iTerm2's Python API on, any program running in an iTerm2 tab (including
coding agents) can control your other tabs without a prompt. Consider blocking `it2`
and `osascript` in your agents' permission or sandbox settings.
NOTE

if [[ "${1:-}" == "--wait" ]]; then
  read -r -s -n 1 -p "Press any key to close." || true
fi
exit "$failed"
