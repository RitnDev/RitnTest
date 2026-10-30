---
name: factorio-mod-ritntest
description: >
  Test a Factorio 2.x mod YOURSELF inside the real game, driven through RCON with the RitnTest development mod:
  fake GUI events (click, checkbox, text, selection, tab, shortcut) sent to the mod's own handlers, GUI tree
  reading, screenshots, Lua evaluation inside the mod VM, errors read from factorio-current.log. Use it whenever
  the user asks to test in game, check that a feature works, reproduce a bug, or says "the game is hosted" —
  even without naming RitnTest. Also guides the one-time setup (RCON, mod links, hosted game).
  Tester soi-même un mod Factorio dans le vrai jeu avec RitnTest.
---

# Testing a Factorio mod in game with RitnTest

RitnTest (https://github.com/RitnDev/RitnTest) adds to the tested mod a remote interface `RitnTest_<mod>`,
run **inside the tested mod VM**. You call it through RCON with `tools/rcon.py` (Python 3, no dependency).

> ⚠ Local test game only. Never install RitnTest on a public server (its `eval` runs any code).

## Paths used below

| Name | What |
|---|---|
| `<RITNTEST>` | the cloned RitnTest repository |
| `<MOD>` | the folder of the mod being tested (its `info.json` gives the mod name) |
| `<DATA>` | Factorio **user data** folder: it holds `config/config.ini`, `mods/`, `script-output/`, `factorio-current.log`. Installed game: `%APPDATA%\Factorio` (Windows), `~/.factorio` (Linux), `~/Library/Application Support/factorio` (macOS). Portable (zip) game: the game folder itself. A separate portable install for tests is recommended. |

Ask the user for `<RITNTEST>`, `<MOD>` and `<DATA>` once, then reuse them.

## One-time setup (do it with the user)

1. **RCON** — the game must be **closed** (it rewrites `config.ini` when it quits). In `<DATA>/config/config.ini`,
   section `[other]`, set (uncomment):
   ```ini
   local-rcon-socket=127.0.0.1:27015
   local-rcon-password=<any password>
   ```
   Keep `127.0.0.1` (local only). `rcon.py` reads these two values; the password never goes into a repository.
2. **Mods** — link the repositories into `<DATA>/mods` (the folder name must be the mod name):
   - Windows (no admin needed): `cmd /c mklink /J "<DATA>\mods\RitnTest" "<RITNTEST>"` and the same for `<MOD>`;
   - Linux / macOS: `ln -s "<RITNTEST>" "<DATA>/mods/RitnTest"` and the same for `<MOD>`.
   Dependencies of the mod (e.g. RitnLib) must be in `mods` too (link or zip from the mod portal).
3. **Hook in the tested mod** — in its `control.lua`, while it loads (not inside an event):
   ```lua
   if script.active_mods["RitnTest"] then
       require("__RitnTest__.interface")
   end
   ```
   It does nothing for players who don't have RitnTest. No dependency to declare.
4. **Errors** — if the mod catches its own GUI errors (pcall), it must also `log()` them with the call stack,
   otherwise they only show in the chat and you can't see them.
5. **Game** — the user starts Factorio and chooses **Multiplayer → Host game** (RCON only works in a hosted
   game). The user must not open the mod windows: the test does.

## RCON client

Run from `<RITNTEST>`. The data folder is passed in **every** bash command (the shell starts fresh each call):

```bash
export RITNTEST_FACTORIO='<DATA>'
python tools/rcon.py call <mod> ping
python tools/rcon.py call <mod> <function> <arguments...>
python tools/rcon.py screenshot <mod> 1 <name>
python tools/rcon.py cmd "/silent-command rcon.print(game.tick)"
```

- `call` = `remote.call("RitnTest_<mod>", ...)`; `cmd` runs in the scenario VM, not the mod VM.
- Arguments are written as is if they look like Lua (number, true, false, nil, `{...}`), otherwise as strings.
- The first Lua command of a game may return an empty line (achievements warning, sent again automatically):
  start with a `ping`.

## Interface functions

| Function | Role |
|---|---|
| `ping` | mod name (checks that everything is plugged in) |
| `click p sel [left/right/middle] [shift+control]` | click; returns `filtered` if `mouse_button_filter` refuses the button |
| `check p sel true/false`, `text p sel "..."`, `confirm p sel` | checkbox, text (+ text_changed), Enter |
| `select p sel index`, `tab p sel index`, `slide p sel value`, `close p sel` | list, tab, slider, closing |
| `input p custom-input-name` | mod keyboard shortcut |
| `exists p sel`, `describe p sel [depth=3]` | existence; GUI tree as text (names, types, captions, styles, tags) |
| `screenshot p name` | screenshot with the GUI (prefer the `screenshot` mode of rcon.py) |
| `eval "expr"` | Lua inside the mod VM (storage, classes, `package.loaded[...]`); returns `error: ...` on error |

`p` = player index (usually 1). Answers: `ok`, `no handler`, `filtered`, `error: <message>`.
**`ok` doesn't prove there was no error**: the mod may have caught it → always check the log.

### Selector (`sel`)

- a name: `mymod_panel-button-close` (searched in the whole player GUI);
- a list of steps: `'{"mymod_tree-pane-tree",{key="players"},"mymod_tree-button-key"}'`
  — `"name"`: descendant with this name; number: child at this position; `{tag=value}`: descendant whose tags match
  (unnamed rows). In bash, put the list between single quotes.

## Running a test

1. `ping`, then count the `ERROR` lines of the log:
   `L='<DATA>/factorio-current.log'; c0=$(grep -c ERROR "$L")`.
2. Chain the actions inside **one bash command** (fewer round trips).
3. Check the real state with `describe` / `eval`, not only the `ok` answers.
4. Screenshots only for the rendering (colours, alignment, icons), and few of them.
5. At the end: `echo "errors: $(( $(grep -c ERROR "$L") - c0 ))"`, read the new ones (`grep -n ERROR -A4 "$L" | tail`),
   and tell the expected ones (wanted error messages) from the real ones.
6. Put back what the test changed (open windows, settings).

## Known pitfalls

- **Files changed → restart Factorio** and host again: `game.reload_script()` doesn't read the disk again, and the
  data stage (prototypes, styles) is only read at start. Ask the user to do it.
- **`require` is forbidden during the game** (outside control.lua loading): "Require can't be used outside of
  control.lua parsing". Out-of-game simulations don't see it.
- **No `debug.getupvalue`**: a local function (e.g. a command handler) can't be reached. A command sent through RCON
  has **no player**: test what it calls through `eval`, or ask the user to type the command.
- **Mod settings** (`settings.global`) can only be changed by the mod that declares them → use `eval`.
- **Screenshot right after an action**: values refreshed on the next tick may be missing; check with `describe`.
- **Compare with the published version**: put the portal zip in `mods`, pin `"version"` in `mod-list.json`, new map;
  the published version doesn't load RitnTest → the user does the clicks, screenshots go through `rcon.py cmd`
  (`game.take_screenshot{player=p, by_player=p, show_gui=true, path="RitnTest/x.png"}`).

## Report to the user

Short: what passed in one sentence, then only the failures with their reason and what was fixed.
