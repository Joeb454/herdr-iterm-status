#!/bin/bash
# locales/*.json: every language is complete, plurals follow CLDR, language follows macOS.

test_all_locales_have_all_keys() {
  local lang missing
  for lang in de ja pt-BR ru zh-Hans; do
    [[ -f "$ROOT/locales/$lang.json" ]] || { echo "    missing locales/$lang.json" >&2; return 1; }
    missing="$(jq -r --slurpfile en "$ROOT/locales/en.json" \
      '($en[0] | keys | map(select(startswith("_") | not))) - keys | join(",")' "$ROOT/locales/$lang.json")"
    assert_eq "" "$missing" "$lang has every en key"
    jq -e '[.needs_input, .working, .done][] | has("other")' "$ROOT/locales/$lang.json" >/dev/null \
      || { echo "    $lang plural without other" >&2; return 1; }
  done
  jq -e '[.needs_input, .working, .done][] | has("one") and has("few") and has("many")' "$ROOT/locales/ru.json" >/dev/null \
    || { echo "    ru needs one/few/many" >&2; return 1; }
}

# working_status <n> <config-json> <apple-langs> -> the --status= value for n working agents
working_status() {
  local list="" i
  for ((i = 0; i < $1; i++)); do list="$list,{\"agent\":\"claude\",\"agent_status\":\"working\",\"workspace_id\":\"w84\"}"; done
  run_status "[${list#,}]" "${2:-}" "${3:-}" | sed -n 's/^--status=//p'
}

test_ru_plurals() {
  local cfg='{"language":"ru"}' one few many
  one="$(jq -r '.working.one' "$ROOT/locales/ru.json")"
  few="$(jq -r '.working.few' "$ROOT/locales/ru.json")"
  many="$(jq -r '.working.many' "$ROOT/locales/ru.json")"
  assert_eq "${one//\{count\}/1}" "$(working_status 1 "$cfg")" "1 → one"
  assert_eq "${few//\{count\}/2}" "$(working_status 2 "$cfg")" "2 → few"
  assert_eq "${many//\{count\}/5}" "$(working_status 5 "$cfg")" "5 → many"
  assert_eq "${many//\{count\}/11}" "$(working_status 11 "$cfg")" "11 → many"
  assert_eq "${one//\{count\}/21}" "$(working_status 21 "$cfg")" "21 → one"
  assert_eq "${few//\{count\}/22}" "$(working_status 22 "$cfg")" "22 → few"
  assert_eq "${few//\{count\}/24}" "$(working_status 24 "$cfg")" "24 → few"
  assert_eq "${many//\{count\}/14}" "$(working_status 14 "$cfg")" "14 → many"
}

test_language_from_apple_langs() {
  local ja
  ja="$(jq -r '.working.other' "$ROOT/locales/ja.json")"
  assert_eq "${ja//\{count\}/2}" "$(working_status 2 '' '("ja-JP", "en-GB")')" "first preferred language wins"
  assert_eq "$(jq -r '.working.other' "$ROOT/locales/pt-BR.json" | sed 's/{count}/2/')" \
    "$(working_status 2 '' '("pt-PT")')" "pt-PT falls to pt-BR"
  assert_eq "2 working" "$(working_status 2 '' '("fr-FR")')" "unsupported → English"
  assert_eq "2 working" "$(working_status 2 '' '("zh-Hant-TW")')" "Traditional Chinese is not zh-Hans"
  assert_eq "2 working" "$(working_status 2 '' '("zh-TW")')" "Taiwan implies Traditional"
  assert_eq "$(jq -r '.working.other' "$ROOT/locales/de.json" | sed 's/{count}/2/')" \
    "$(working_status 2 '' '("de-AT")')" "regional variant falls to its language"
  assert_eq "$(jq -r '.working.other' "$ROOT/locales/zh-Hans.json" | sed 's/{count}/2/')" \
    "$(working_status 2 '' '("zh-Hans-CN")')" "script subtag matches zh-Hans"
}
