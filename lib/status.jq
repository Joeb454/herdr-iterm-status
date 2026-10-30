# Pure decision logic: herdr agent/workspace lists + config + locales -> it2 set-status argv.
# Every value that reaches it2 is built here, so the shell never interpolates untrusted text.

def config: reduce $config[] as $c ({}; . * $c);

def sanitise($max):
  tostring
  | gsub("[\\t\\n\\r]"; " ")
  # Controls and format characters (zero-width, bidi, tags): an agent title must not be able to
  # emit escapes or visually reorder the subtitle.
  | gsub("[\\p{Cc}\\p{Cf}]"; "")
  | gsub("\\s+"; " ")
  | ltrimstr(" ") | rtrimstr(" ")
  | if length > $max then .[0:$max - 1] + "…" else . end;

def supported: [$locales[] | ._lang];

# AppleLanguages is a plist array printed by `defaults`, e.g. ( "en-GB", "ja-JP" ).
def preferred_languages: [$apple_langs | scan("\"([^\"]+)\"") | .[0]];

# Traditional Chinese must not fall through to zh-Hans: English beats the wrong script.
def traditional_chinese: test("^zh-(Hant|TW|HK|MO)(-|$)");

def pick_language:
  supported as $s
  | (config.language // "auto") as $want
  | if $want != "auto" and ($s | index($want)) then $want
    else
      first(
        (preferred_languages[] as $p
          | ($s[] | select(. == $p)),
            ($s[] | . as $l | select($p | startswith($l + "-"))),
            ($s[] | select(($p | traditional_chinese | not)
                           and (split("-")[0]) == ($p | split("-")[0])))),
        "en")
    end;

def locale($lang):
  ($locales | map(select(._lang == "en"))[0]) * ($locales | map(select(._lang == $lang))[0] // {})
  * (config.strings // {});

# CLDR cardinal plural categories for the shipped languages.
def plural($lang; $n):
  if $lang == "ru" then
    if ($n % 10) == 1 and ($n % 100) != 11 then "one"
    elif ($n % 10) >= 2 and ($n % 10) <= 4 and (($n % 100) < 12 or ($n % 100) > 14) then "few"
    else "many" end
  elif $lang == "pt-BR" then (if $n == 0 or $n == 1 then "one" else "other" end)
  elif $lang == "en" or $lang == "de" then (if $n == 1 then "one" else "other" end)
  else "other" end;

def fill($vars): reduce ($vars | to_entries[]) as $v (.; gsub("\\{" + $v.key + "\\}"; $v.value | tostring));

def counted($strings; $lang; $key; $n):
  ($strings[$key]) as $forms
  | ($forms[plural($lang; $n)] // $forms.other) | fill({count: $n});

def clear_args: ["session", "set-status", "--status", "", "--dot-color", "", "--text-color", ""];

config as $cfg
| ($cfg.max_title_length // 48) as $max
| ($agents[0].result.agents // []) as $all
| ($workspaces[0].result.workspaces // []) as $spaces
| pick_language as $lang
| locale($lang) as $s
| [$all[] | .agent_status | if . == "unknown" or . == null then "idle" else . end] as $states
| {
    blocked: ($states | map(select(. == "blocked")) | length),
    working: ($states | map(select(. == "working")) | length),
    done: (if $cfg.show_done == false then 0 else ($states | map(select(. == "done")) | length) end)
  } as $n
| if ($all | length) == 0 then {action: "clear", args: clear_args}
  else
    (if $n.blocked > 0 then "blocked" elif $n.working > 0 then "working"
     elif $n.done > 0 then "done" else "idle" end) as $top
    | (if $n.blocked == 1 then
        ($all[] | select(.agent_status == "blocked")) as $a
        | (($a.terminal_title_stripped // "") | sanitise($max)) as $t
        | (if $t == "" then ($a.agent // "agent" | sanitise($max)) else $t end) as $title
        | (($spaces[] | select(.workspace_id == $a.workspace_id) | .label | sanitise($max)) // "") as $space
        # The named phrase alone: counts would push the name out of a narrow tab.
        | [if $space == "" then $s.needs_input_unnamed | fill({agent: $title})
           else $s.needs_input_named | fill({agent: $title, space: $space}) end]
      elif $top == "idle" then [$s.idle]
      else
        [ (if $n.blocked > 0 then counted($s; $lang; "needs_input"; $n.blocked) else empty end),
          (if $n.working > 0 then counted($s; $lang; "working"; $n.working) else empty end),
          (if $n.done > 0 then counted($s; $lang; "done"; $n.done) else empty end) ]
      end) as $parts
    | ($cfg.colors[$top]) as $color
    | {action: "set",
       args: ["session", "set-status",
              "--status=" + ($parts | join($s.separator)),
              "--dot-color=" + $color, "--text-color=" + $color]}
  end
