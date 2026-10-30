# herdr iTerm Status

A [herdr](https://herdr.dev) plugin that shows what your agents are doing on the iTerm2 tab running herdr. The tab's subtitle line and dot show the most urgent state across every space:

| Situation | Subtitle | Colour |
|---|---|---|
| One agent needs input | `Needs input: <agent title> · <space>` | red |
| Several need input | `2 need input · 3 working · 1 done` | red |
| Agents working | `3 working · 1 done` | amber |
| Finished, not yet looked at | `1 done` | blue |
| Everything idle | `idle` | grey |

The tab title itself stays herdr's (`ui.window_title`). The subtitle clears when you detach or quit herdr.

<!-- screenshot -->

## Requirements

- macOS with iTerm2 3.7 or later
- herdr 0.9.5 or later
- Nothing else: the plugin is Bash and `jq`, both of which ship with macOS

## Install

```bash
herdr plugin link /path/to/this/repo
```

### Turn on iTerm2's Python API

The plugin talks to iTerm2 through `it2`, which needs the Python API:

1. In iTerm2, open **Settings → General → Magic**.
2. Tick **Enable Python API**.
3. If iTerm2 asks whether to allow a connection, choose **Allow**.

Then check everything is in place. Either bind the action to a key, or run:

```bash
herdr plugin action invoke joeb454.iterm-status.doctor
```

A popup lists each check, with the fix for anything that fails. If the API is off, the plugin shows one herdr notification per server run pointing you here.

## Settings

Optional. Create `config.json` in the directory printed by `herdr plugin config-dir joeb454.iterm-status`. Any key you leave out keeps its default:

```json
{
  "language": "auto",
  "show_done": true,
  "max_title_length": 48,
  "colors": {
    "blocked": "#ff5f57",
    "working": "#e0a030",
    "done": "#4a9eff",
    "idle": "#8e8e93"
  },
  "strings": {}
}
```

- `language`: `auto`, or one of `en`, `de`, `ja`, `pt-BR`, `ru`, `zh-Hans`.
- `show_done`: count agents that finished but you haven't looked at yet.
- `max_title_length`: longer agent titles are cut with `…`.
- `colors`: the dot and subtitle colour for the most urgent state.
- `strings`: override any phrase from `locales/<lang>.json`, e.g. `{"idle": "all quiet"}`.

An invalid `config.json` is ignored with a warning, and the defaults are used.

## Languages

English, German, Japanese, Brazilian Portuguese, Russian and Simplified Chinese: the languages iTerm2 ships in. With `language: "auto"`, the first match from macOS's preferred languages is used, falling back to English. Plurals follow each language's rules.

The non-English strings are machine-drafted and not yet reviewed by native speakers. Corrections are welcome.

## Security

- **Agent titles are untrusted.** Any program in a pane can set its title. Titles are stripped of control characters, escape sequences, zero-width and bidi characters, and capped in length. All logic runs in `jq`, and Bash only passes a fixed argument array to `it2`. Nothing is evaluated.
- **The Python API widens what programs in iTerm2 can do.** With it on, any program running in any iTerm2 tab, including coding agents, can control your other tabs (type into them, read their screens) without a prompt. iTerm2 has no per-tab or ask-first setting. Much of this was already possible through iTerm2's AppleScript support. Consider blocking `it2` and `osascript` in your agents' permission or sandbox settings.

## Limits

- iTerm2 only. Other terminals get nothing.
- herdr attached over SSH (`--remote`) or used through `--machine` isn't supported.
- Each herdr session updates only the iTerm2 tabs attached to that session.

## Development

```bash
tests/run.sh                                  # all tests
tests/run.sh status                           # one file
shellcheck bin/*.sh lib/*.sh tests/*.sh
```
