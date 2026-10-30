#!/bin/bash
# lib/clients.sh: which herdr clients belong to a session, and which iTerm tabs show them.

# A stub ps: answers `ps -o tty= -p PID` from a fixed table.
make_stub_ps() {
  cat > "$TEST_TMP/ps" <<'STUB'
#!/bin/bash
case "${*: -1}" in
  7661) echo "ttys000" ;;
  9101) echo "ttys005" ;;
  9201) echo "ttys007" ;;
  *) echo "??" ;;
esac
STUB
  chmod +x "$TEST_TMP/ps"
  export PS_BIN="$TEST_TMP/ps"
}

test_finds_default_client() {
  make_stub_ps
  load_lib clients
  local out
  out="$(client_pids_and_ttys /Users/test/.config/herdr/herdr-client.sock < "$FIXTURES/lsof-default.txt")"
  assert_eq "$(printf '7661\t/dev/ttys000')" "$out" "default session's single client"
}

test_ignores_other_session() {
  make_stub_ps
  load_lib clients
  local out
  out="$(client_pids_and_ttys /Users/test/.config/herdr/herdr-client.sock < "$FIXTURES/lsof-two-sessions.txt")"
  assert_eq "$(printf '7661\t/dev/ttys000')" "$out" "default socket sees only its client"
  out="$(client_pids_and_ttys /Users/test/.config/herdr/sessions/seize/herdr-client.sock < "$FIXTURES/lsof-two-sessions.txt")"
  assert_eq "$(printf '9101\t/dev/ttys005')" "$out" "seize socket sees only its client"
}

test_socket_path_with_spaces() {
  make_stub_ps
  load_lib clients
  local out
  out="$(client_pids_and_ttys "/Users/test/My Configs/herdr/herdr-client.sock" < "$FIXTURES/lsof-two-sessions.txt")"
  assert_eq "$(printf '9201\t/dev/ttys007')" "$out" "path with a space"
}

test_skips_client_without_tty() {
  make_stub_ps
  load_lib clients
  local out
  out="$(sed 's/ 7661 / 7999 /' "$FIXTURES/lsof-default.txt" | client_pids_and_ttys /Users/test/.config/herdr/herdr-client.sock)"
  assert_eq "" "$out" "no tty, no client"
}

test_maps_tty_to_iterm_session() {
  load_lib clients
  local out
  out="$(iterm_sessions_for_ttys /dev/ttys000 < "$FIXTURES/it2-list.txt")"
  assert_eq "$(printf '099EBE12-4983-4FD1-9C73-64D7E9FE9D7F\t/dev/ttys000')" "$out" "tty maps to session id"
}

test_unmatched_tty_prints_nothing() {
  load_lib clients
  local out
  out="$(iterm_sessions_for_ttys /dev/ttys999 < "$FIXTURES/it2-list.txt")"
  assert_eq "" "$out" "unknown tty"
}

test_tab_in_tab_name_does_not_shift_columns() {
  load_lib clients
  local out
  out="$(printf 'AAAA\tname\twith tab\ttitle\t10x10\t\\/dev\\/ttys003\n' | iterm_sessions_for_ttys /dev/ttys003)"
  assert_eq "$(printf 'AAAA\t/dev/ttys003')" "$out" "id is first field, tty is last"
}
