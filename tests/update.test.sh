#!/bin/bash
# bin/update.sh end to end, with herdr, it2, lsof, ps and defaults stubbed.



# Last it2 set-status call, one argv element per line.
last_it2_call() {
  local f
  f="$(find "$TEST_TMP/calls" -type f 2>/dev/null | sort | tail -1)"
  [[ -n "$f" ]] && tr '\0' '\n' < "$f"
}

it2_call_count() {
  find "$TEST_TMP/calls" -type f 2>/dev/null | wc -l | tr -d ' '
}

BLOCKED_ROADMAP='{"agent":"claude","agent_status":"blocked","workspace_id":"w84","terminal_title_stripped":"Project roadmap next steps"}'

test_sets_status_on_matching_tab() {
  setup_update_env
  set_agents "[$BLOCKED_ROADMAP]"
  /bin/bash "$ROOT/bin/update.sh"
  assert_eq "$(printf 'session\nset-status\n--session=099EBE12-4983-4FD1-9C73-64D7E9FE9D7F\n--status=Needs input: Project roadmap next steps · infrastructure\n--dot-color=#ff5f57\n--text-color=#ff5f57\n')" \
    "$(last_it2_call)" "exact argv to it2"
}

test_hostile_title_argv() {
  setup_update_env
  local long hostile
  long="$(printf 'x%.0s' $(seq 1 5000))"
  hostile="--session=\$(touch $TEST_TMP/pwned)\`touch $TEST_TMP/pwned2\`; rm -rf ~ "$'\e]1337;x\a'" $long"
  set_agents "[$(jq -cn --arg t "$hostile" '{agent:"claude",agent_status:"blocked",workspace_id:"w84",terminal_title_stripped:$t}')]"
  /bin/bash "$ROOT/bin/update.sh"
  [[ ! -e "$TEST_TMP/pwned" && ! -e "$TEST_TMP/pwned2" ]] || { echo "    command substitution ran" >&2; return 1; }
  local status
  status="$(last_it2_call | grep -- '^--status=')"
  assert_eq 1 "$(last_it2_call | grep -c -- '^--status=')" "one --status element"
  assert_eq 6 "$(last_it2_call | wc -l | tr -d ' ')" "argv count unchanged"
  assert_contains "--status=Needs input: --session=\$(touch" "$status" "title kept as literal text"
  [[ ${#status} -le 90 ]] || { echo "    status not truncated: ${#status}" >&2; return 1; }
}

test_user_config_overrides() {
  setup_update_env
  set_agents "[$BLOCKED_ROADMAP]"
  echo '{"colors":{"blocked":"#000000"}}' > "$TEST_TMP/config/config.json"
  /bin/bash "$ROOT/bin/update.sh"
  assert_contains "--dot-color=#000000" "$(last_it2_call)" "user colour wins"
}

test_invalid_config_falls_back() {
  setup_update_env
  set_agents "[$BLOCKED_ROADMAP]"
  echo '{"colors":' > "$TEST_TMP/config/config.json"
  local err
  err="$(/bin/bash "$ROOT/bin/update.sh" 2>&1 >/dev/null)"
  assert_contains "--dot-color=#ff5f57" "$(last_it2_call)" "defaults used"
  assert_contains "config.json" "$err" "warning names the file"
}

test_coalesces_burst() {
  setup_update_env
  export STUB_IT2_DELAY=0.2
  set_agents "[$BLOCKED_ROADMAP]"
  for _ in 1 2 3 4 5 6 7 8 9; do /bin/bash "$ROOT/bin/update.sh" & done
  set_agents '[{"agent":"claude","agent_status":"working","workspace_id":"w84"}]'
  /bin/bash "$ROOT/bin/update.sh" &
  wait
  assert_eq "" "$(paste -sd' ' "$TEST_TMP/timeline" | sed 's/start end//g' | tr -d ' ')" "it2 calls never overlap"
  [[ "$(it2_call_count)" -lt 10 ]] || { echo "    no coalescing: $(it2_call_count) calls" >&2; return 1; }
  assert_contains "--status=1 working" "$(last_it2_call)" "final state wins"
}

test_no_client_noop() {
  setup_update_env
  set_agents "[$BLOCKED_ROADMAP]"
  printf '#!/bin/bash\necho "??"\n' > "$TEST_TMP/bin/ps"
  /bin/bash "$ROOT/bin/update.sh"
  assert_eq 0 "$(it2_call_count)" "nothing to update"
}

test_second_client_on_other_tty_still_succeeds() {
  setup_update_env
  set_agents "[$BLOCKED_ROADMAP]"
  sleep 5 &
  export STUB_CLIENT2_PID=$!
  # The second client (higher pid, listed last) sits on a tty iTerm doesn't know.
  cat > "$TEST_TMP/bin/lsof" <<'STUB'
#!/bin/bash
sed "s/ 7661 / $STUB_CLIENT_PID /" "$STUB_FIXTURES/lsof-default.txt"
echo "herdr      $STUB_CLIENT2_PID  user   4u  unix 0x9999999999999999      0t0      ->0xaa31870001cecfb6"
STUB
  cat > "$TEST_TMP/bin/ps" <<'STUB'
#!/bin/bash
case "${*: -1}" in "$STUB_CLIENT_PID") echo ttys000 ;; "$STUB_CLIENT2_PID") echo ttys009 ;; *) echo "??" ;; esac
STUB
  local rc=0
  /bin/bash "$ROOT/bin/update.sh" || rc=$?
  assert_eq 0 "$rc" "hook succeeds"
  assert_contains "--status=Needs input: Project roadmap next steps" "$(last_it2_call)" "tab updated"
}

test_sessions_do_not_share_a_lock() {
  setup_update_env
  set_agents "[$BLOCKED_ROADMAP]"
  # Session A's run holds the lock (slow it2) while session B's hook fires.
  export STUB_IT2_DELAY=1
  /bin/bash "$ROOT/bin/update.sh" &
  local a=$!
  sleep 0.3
  cat > "$TEST_TMP/bin/lsof" <<'STUB'
#!/bin/bash
cat "$STUB_FIXTURES/lsof-two-sessions.txt"
STUB
  cat > "$TEST_TMP/bin/ps" <<'STUB'
#!/bin/bash
[[ "${*: -1}" == "9101" ]] && echo ttys005 || echo "??"
STUB
  printf 'BBBBBBBB-0000-0000-0000-000000000000\tseize\tseize\t80x24\t\\/dev\\/ttys005\n' >> "$TEST_TMP/it2-extra.txt"
  cat "$FIXTURES/it2-list.txt" "$TEST_TMP/it2-extra.txt" > "$TEST_TMP/it2-list.txt"
  sed -i '' "s|\$STUB_FIXTURES/it2-list.txt|$TEST_TMP/it2-list.txt|" "$TEST_TMP/bin/it2"
  HERDR_SOCKET_PATH=/Users/test/.config/herdr/sessions/seize/herdr.sock STUB_IT2_DELAY=0 /bin/bash "$ROOT/bin/update.sh"
  wait "$a"
  grep -rlq -- '--session=BBBBBBBB-0000-0000-0000-000000000000' "$TEST_TMP/calls" \
    || { echo "    session B's tab never updated" >&2; return 1; }
}
