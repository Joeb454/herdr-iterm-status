#!/bin/bash
# Shared test helpers; sourced by tests/run.sh.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034 # used by the sourced test files
FIXTURES="$ROOT/tests/fixtures"

assert_eq() {
  if [[ "$1" != "$2" ]]; then
    printf '    %s\n    expected: %q\n    actual:   %q\n' "$3" "$1" "$2" >&2
    return 1
  fi
}

assert_contains() {
  if [[ "$2" != *"$1"* ]]; then
    printf '    %s\n    expected to contain: %q\n    actual: %q\n' "$3" "$1" "$2" >&2
    return 1
  fi
}

# bash 3.2 can exit 0 when `source` of a missing file fails under set -e, so check first.
load_lib() {
  if [[ ! -f "$ROOT/lib/$1.sh" ]]; then
    echo "    missing lib/$1.sh" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "$ROOT/lib/$1.sh"
}

# Stubs herdr, it2, lsof, ps and defaults, and sets the plugin env a hook would get.
setup_update_env() {
  mkdir -p "$TEST_TMP/bin" "$TEST_TMP/config" "$TEST_TMP/state"
  cp "$FIXTURES/workspaces.json" "$TEST_TMP/workspaces.json"

  cat > "$TEST_TMP/bin/herdr" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "agent list") cat "$STUB_DIR/agents.json" ;;
  "workspace list") cat "$STUB_DIR/workspaces.json" ;;
  "notification show") printf '%s\n' "$*" >> "$STUB_DIR/herdr.log" ;;
  *) exit 2 ;;
esac
STUB
  cat > "$TEST_TMP/bin/it2" <<'STUB'
#!/bin/bash
if [[ "$1 $2" == "session list" ]]; then
  [[ -f "$STUB_DIR/it2-api-off" ]] && { echo "Failed to connect to iTerm2 socket" >&2; exit 1; }
  cat "$STUB_FIXTURES/it2-list.txt"; exit 0
fi
echo "start" >> "$STUB_DIR/timeline"
sleep "${STUB_IT2_DELAY:-0}"
n=$(( $(cat "$STUB_DIR/it2.count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_DIR/it2.count"
mkdir -p "$STUB_DIR/calls"
printf '%s\0' "$@" > "$STUB_DIR/calls/$(printf '%04d' "$n")"
echo "end" >> "$STUB_DIR/timeline"
STUB
  # A short-lived fake client stands in for the fixture's pid, so the watchers update.sh
  # starts track a process this test owns (and that exits on its own).
  sleep 5 &
  export STUB_CLIENT_PID=$!
  cat > "$TEST_TMP/bin/lsof" <<'STUB'
#!/bin/bash
sed "s/ 7661 / $STUB_CLIENT_PID /" "$STUB_FIXTURES/lsof-default.txt"
STUB
  cat > "$TEST_TMP/bin/ps" <<'STUB'
#!/bin/bash
[[ "${*: -1}" == "$STUB_CLIENT_PID" ]] && echo "ttys000" || echo "??"
STUB
  cat > "$TEST_TMP/bin/defaults" <<'STUB'
#!/bin/bash
printf '(\n    "en-GB"\n)\n'
STUB
  chmod +x "$TEST_TMP"/bin/*

  export STUB_DIR="$TEST_TMP" STUB_FIXTURES="$FIXTURES"
  export HERDR_BIN_PATH="$TEST_TMP/bin/herdr" HERDR_ITERM_STATUS_IT2="$TEST_TMP/bin/it2"
  export LSOF_BIN="$TEST_TMP/bin/lsof" PS_BIN="$TEST_TMP/bin/ps" DEFAULTS_BIN="$TEST_TMP/bin/defaults"
  export HERDR_SOCKET_PATH=/Users/test/.config/herdr/herdr.sock TERM_PROGRAM=iTerm.app
  export HERDR_PLUGIN_ROOT="$ROOT" HERDR_PLUGIN_CONFIG_DIR="$TEST_TMP/config" HERDR_PLUGIN_STATE_DIR="$TEST_TMP/state"
}

# set_agents <json-array>
set_agents() {
  printf '{"result":{"agents":%s}}' "$1" > "$TEST_TMP/agents.json"
}
