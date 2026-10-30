#!/bin/bash
# lib/status.jq: agent list + workspaces + config + locales -> it2 argv.

# agent <status> [title] [workspace_id] -> one AgentInfo JSON object
agent() {
  jq -cn --arg s "$1" --arg t "${2-}" --arg w "${3:-w84}" \
    '{agent:"claude", agent_status:$s, workspace_id:$w, pane_id:"\($w):p1"}
     + (if $t == "" then {} else {terminal_title_stripped:$t} end)'
}

# run_status <agents-json-array> [config-override-json] [apple-langs-text]
# Prints the action, then one argv element per line.
run_status() {
  printf '{"result":{"agents":%s}}' "$1" > "$TEST_TMP/agents.json"
  local cfg='{}' langs='("en-GB")'
  [[ -n "${2:-}" ]] && cfg="$2"
  [[ -n "${3:-}" ]] && langs="$3"
  printf '%s' "$cfg" > "$TEST_TMP/user-config.json"
  printf '%s' "$langs" > "$TEST_TMP/langs.txt"
  cat "$ROOT"/locales/*.json > "$TEST_TMP/locales.json"
  jq -nr -f "$ROOT/lib/status.jq" \
    --slurpfile agents "$TEST_TMP/agents.json" \
    --slurpfile workspaces "$FIXTURES/workspaces.json" \
    --slurpfile config <(cat "$ROOT/config.default.json" "$TEST_TMP/user-config.json") \
    --slurpfile locales "$TEST_TMP/locales.json" \
    --rawfile apple_langs "$TEST_TMP/langs.txt" | jq -r '.action, .args[]'
}

set_lines() {
  printf 'set\nsession\nset-status\n--status=%s\n--dot-color=%s\n--text-color=%s' "$1" "$2" "$2"
}

test_one_blocked_named() {
  local out
  out="$(run_status "[$(agent blocked 'Project roadmap next steps'),$(agent working),$(agent working)]")"
  assert_eq "$(set_lines 'Needs input: Project roadmap next steps · infrastructure' '#ff5f57')" "$out" "one blocked is named with its space"
}

test_two_blocked_counts() {
  local out
  out="$(run_status "[$(agent blocked a),$(agent blocked b),$(agent working),$(agent working),$(agent 'done')]")"
  assert_eq "$(set_lines '2 need input · 2 working · 1 done' '#ff5f57')" "$out" "two blocked are counted"
}

test_working_and_done() {
  local out list=""
  for _ in 1 2 3 4 5 6 7 8 9; do list="$list,$(agent idle)"; done
  out="$(run_status "[$(agent working),$(agent working),$(agent 'done')$list]")"
  assert_eq "$(set_lines '2 working · 1 done' '#e0a030')" "$out" "idle is not counted"
}

test_done_only() {
  local out
  out="$(run_status "[$(agent 'done'),$(agent idle),$(agent idle),$(agent idle)]")"
  assert_eq "$(set_lines '1 done' '#4a9eff')" "$out" "done alone is blue"
}

test_show_done_false() {
  local out
  out="$(run_status "[$(agent 'done'),$(agent idle)]" '{"show_done":false}')"
  assert_eq "$(set_lines 'idle' '#8e8e93')" "$out" "hidden done falls through to idle"
}

test_all_idle_including_unknown() {
  local out
  out="$(run_status "[$(agent idle),$(agent unknown)]")"
  assert_eq "$(set_lines 'idle' '#8e8e93')" "$out" "unknown counts as idle"
}

test_no_agents_clears() {
  local out
  out="$(run_status "[]")"
  assert_eq "$(printf 'clear\nsession\nset-status\n--status\n\n--dot-color\n\n--text-color\n')" "$out" "no agents clears the status"
}

test_blank_title_falls_back_to_agent() {
  local out
  out="$(run_status "[$(agent blocked '')]")"
  assert_eq "$(set_lines 'Needs input: claude · infrastructure' '#ff5f57')" "$out" "missing title uses the agent name"
  out="$(run_status '[{"agent":"claude","agent_status":"blocked","workspace_id":"w84","terminal_title_stripped":"   "}]')"
  assert_eq "$(set_lines 'Needs input: claude · infrastructure' '#ff5f57')" "$out" "whitespace title uses the agent name"
}

test_unknown_workspace() {
  local out
  out="$(run_status "[$(agent blocked 'Roadmap' wZZ)]")"
  assert_eq "$(set_lines 'Needs input: Roadmap' '#ff5f57')" "$out" "no space, no separator"
}

test_sanitises_controls() {
  local out
  out="$(run_status '[{"agent":"claude","agent_status":"blocked","workspace_id":"w84","terminal_title_stripped":"a\u001b]0;pwn\u0007b\nc\u009bd"}]')"
  assert_eq "$(set_lines 'Needs input: a]0;pwnb cd · infrastructure' '#ff5f57')" "$out" "C0/C1 stripped, newline to space"
}

test_strips_bidi_and_zero_width() {
  local out
  out="$(run_status '[{"agent":"claude","agent_status":"blocked","workspace_id":"w84","terminal_title_stripped":"safe‮evil​⁦x"}]')"
  assert_eq "$(set_lines 'Needs input: safeevilx · infrastructure' '#ff5f57')" "$out" "bidi and zero-width stripped"
}

test_truncates() {
  local out title
  title="$(printf 'é%.0s' $(seq 1 60))"
  out="$(run_status "[$(agent blocked "$title")]")"
  assert_eq "$(set_lines "Needs input: $(printf 'é%.0s' $(seq 1 47))… · infrastructure" '#ff5f57')" "$out" "47 code points plus ellipsis"
}

test_sanitises_space_name() {
  local out
  out="$(run_status "[$(agent blocked 'Roadmap' wEV)]")"
  assert_eq "$(set_lines 'Needs input: Roadmap · evilspace' '#ff5f57')" "$out" "space names are sanitised too"
}

test_leading_dashes_stay_in_value() {
  local out
  out="$(run_status "[$(agent blocked '--session=x')]")"
  assert_eq "$(set_lines 'Needs input: --session=x · infrastructure' '#ff5f57')" "$out" "dashes stay inside the --status= element"
}
