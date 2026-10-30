#!/bin/bash
# bin/doctor.sh and update.sh's one-time nudge when the Python API is unreachable.

test_doctor_all_good() {
  setup_update_env
  local out
  out="$(/bin/bash "$ROOT/bin/doctor.sh")"
  assert_eq 4 "$(grep -c '^✓' <<< "$out")" "four passing checks"
  assert_contains "Python API" "$out" "the security note is shown"
}

test_doctor_api_off() {
  setup_update_env
  touch "$TEST_TMP/it2-api-off"
  local out rc=0
  out="$(/bin/bash "$ROOT/bin/doctor.sh")" || rc=$?
  assert_eq 1 "$rc" "exit 1"
  assert_contains "Enable Python API" "$(grep -A1 '^✗' <<< "$out")" "fix step on the failing line"
}

test_doctor_missing_it2() {
  setup_update_env
  export HERDR_ITERM_STATUS_IT2="$TEST_TMP/bin/nope"
  local out rc=0
  out="$(/bin/bash "$ROOT/bin/doctor.sh")" || rc=$?
  assert_eq 1 "$rc" "exit 1"
  assert_contains "3.7" "$(grep -A1 '^✗' <<< "$out" | head -2)" "asks for iTerm 3.7+"
}

test_doctor_bad_config() {
  setup_update_env
  echo '{' > "$TEST_TMP/config/config.json"
  local out rc=0
  out="$(/bin/bash "$ROOT/bin/doctor.sh")" || rc=$?
  assert_eq 1 "$rc" "exit 1"
  assert_contains "config.json" "$(grep -A1 '^✗' <<< "$out")" "names the bad file"
}

test_nudge_once_per_server() {
  setup_update_env
  set_agents '[{"agent":"claude","agent_status":"working","workspace_id":"w84"}]'
  touch "$TEST_TMP/it2-api-off"
  /bin/bash "$ROOT/bin/update.sh"
  /bin/bash "$ROOT/bin/update.sh"
  /bin/bash "$ROOT/bin/update.sh"
  assert_eq 1 "$(grep -c '^notification show' "$TEST_TMP/herdr.log")" "one nudge"
  assert_contains "joe.iterm-status.doctor" "$(cat "$TEST_TMP/herdr.log")" "points at the doctor action"
}
