#!/bin/bash
# herdr hook: recompute this session's aggregate agent state and push it to every
# iTerm tab attached to the session.
set -euo pipefail

ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE="${HERDR_PLUGIN_STATE_DIR:?HERDR_PLUGIN_STATE_DIR is not set}"
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-}"
HERDR="${HERDR_BIN_PATH:-herdr}"
LSOF_BIN="${LSOF_BIN:-/usr/sbin/lsof}"
DEFAULTS_BIN="${DEFAULTS_BIN:-/usr/bin/defaults}"

# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/clients.sh
source "$ROOT/lib/clients.sh"
# shellcheck source=lib/watch.sh
source "$ROOT/lib/watch.sh"

# The plugin's state dir is shared by every herdr session, so lock, dirty flag and scratch
# files are per session: one session's run must never swallow another's update.
SESSION_STATE="$STATE/session-$(printf '%s' "${HERDR_SOCKET_PATH:?HERDR_SOCKET_PATH is not set}" | cksum | cut -d' ' -f1)"
LOCK="$SESSION_STATE/lock"
DIRTY="$SESSION_STATE/dirty"
WORK="$SESSION_STATE/work"

acquire_lock() {
  if mkdir "$LOCK" 2>/dev/null; then
    echo "$$" > "$LOCK/pid"
    return 0
  fi
  local holder
  holder="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
    return 1
  fi
  # An empty pid file is a holder mid-startup unless the lock is old enough to be orphaned.
  if [[ -z "$holder" && -z "$(find "$LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; then
    return 1
  fi
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || return 1
  echo "$$" > "$LOCK/pid"
}

release_lock() {
  rm -rf "$LOCK"
}

# One notification per server run (hooks are children of the server, so $PPID names it).
# Only for herdr started from iTerm2: anyone else would be nagged about a tool they don't use.
nudge_api_off() {
  [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]] || return 0
  local marker="$SESSION_STATE/nudged-$PPID"
  [[ -e "$marker" ]] && return 0
  touch "$marker"
  "$HERDR" notification show "iTerm status needs the Python API" \
    --body "Run: herdr plugin action invoke joe.iterm-status.doctor" >/dev/null 2>&1 || true
}

# Writes the jq inputs to $WORK and prints the it2 argv NUL-separated.
compute_args() {
  mkdir -p "$WORK"
  "$HERDR" agent list > "$WORK/agents.json"
  "$HERDR" workspace list > "$WORK/workspaces.json"
  cat "$ROOT"/locales/*.json > "$WORK/locales.json"
  cp "$ROOT/config.default.json" "$WORK/config.json"
  local user="$CONFIG_DIR/config.json"
  if [[ -n "$CONFIG_DIR" && -f "$user" ]]; then
    if jq -e 'type == "object"' "$user" >/dev/null 2>&1; then
      cat "$user" >> "$WORK/config.json"
    else
      echo "iterm-status: ignoring invalid $user (using defaults)" >&2
    fi
  fi
  "$DEFAULTS_BIN" read -g AppleLanguages > "$WORK/langs.txt" 2>/dev/null || : > "$WORK/langs.txt"

  jq -n -f "$ROOT/lib/status.jq" \
    --slurpfile agents "$WORK/agents.json" \
    --slurpfile workspaces "$WORK/workspaces.json" \
    --slurpfile config "$WORK/config.json" \
    --slurpfile locales "$WORK/locales.json" \
    --rawfile apple_langs "$WORK/langs.txt" \
    | jq -j '.args[] | . + "\u0000"'
}

update_once() {
  local sock clients sessions pid tty sid line
  sock="$(dirname "${HERDR_SOCKET_PATH:?HERDR_SOCKET_PATH is not set}")/herdr-client.sock"
  clients="$("$LSOF_BIN" -nP -U -c herdr 2>/dev/null | client_pids_and_ttys "$sock")"
  [[ -n "$clients" ]] || return 0

  local ttys=()
  while IFS=$'\t' read -r pid tty; do ttys+=("$tty"); done <<< "$clients"
  local list
  if ! list="$(run_it2 session list 2>/dev/null)"; then
    nudge_api_off
    return 0
  fi
  sessions="$(iterm_sessions_for_ttys "${ttys[@]}" <<< "$list")"
  [[ -n "$sessions" ]] || return 0

  local args=() a
  while IFS= read -r -d '' a; do args+=("$a"); done < <(compute_args)
  [[ ${#args[@]} -ge 2 ]] || return 0

  while IFS=$'\t' read -r sid tty; do
    # Session ids come from iTerm, but they still end up in argv: accept only the UUID shape.
    [[ "$sid" =~ ^[A-Fa-f0-9-]+$ ]] || continue
    run_it2 "${args[0]}" "${args[1]}" "--session=$sid" "${args[@]:2}" >/dev/null || true
    while IFS=$'\t' read -r pid line; do
      if [[ "$line" == "$tty" ]]; then
        start_watcher "$pid" "$sid" "$tty"
      fi
    done <<< "$clients"
  done <<< "$sessions"
  return 0
}

mkdir -p "$SESSION_STATE"
# Mark dirty before trying the lock: a holder that is just finishing re-checks this flag
# after releasing, so a burst never ends on a stale state.
touch "$DIRTY"
while [[ -e "$DIRTY" ]]; do
  acquire_lock || exit 0
  trap release_lock EXIT
  while [[ -e "$DIRTY" ]]; do
    rm -f "$DIRTY"
    # One failed pass must not end the loop: a newer run's dirty flag would be stranded.
    update_once || true
  done
  release_lock
  trap - EXIT
done
