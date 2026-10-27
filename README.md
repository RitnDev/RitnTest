# RitnTest

FR : Outil de développement (jamais publié) pour tester les mods Ritn dans le vrai jeu, piloté par RCON.
EN : Development tool (never published) to test Ritn mods inside the real game, driven through RCON.

## Mod testé / Tested mod

FR : Ajouter au chargement du `control.lua` du mod testé (pas dans un évènement) :
EN : Add at the tested mod `control.lua` loading (not inside an event):

```lua
if script.active_mods["RitnTest"] then require("__RitnTest__.interface") end
```

FR : L'interface remote `RitnTest_<mod>` est alors disponible (voir `interface.lua`) :
`ping`, `click`, `check`, `text`, `confirm`, `select`, `tab`, `slide`, `close`, `input`, `exists`,
`describe`, `screenshot`, `eval`.
EN : The remote interface `RitnTest_<mod>` is then available (see `interface.lua`).

## Partie de test / Test game

1. FR : `config/config.ini` de Factorio, section `[other]` / EN : Factorio `config/config.ini`, `[other]` section :
   `local-rcon-socket=127.0.0.1:27015`, `local-rcon-password=...`
2. FR : Jonctions des mods dans le dossier `mods` (`mklink /J`) / EN : Mod junctions inside the `mods` folder.
3. FR : « Héberger une partie » (RCON ne marche qu'en multijoueur) / EN : "Host game" (RCON only works in multiplayer).

## Client RCON

```
python tools/rcon.py call gvv ping
python tools/rcon.py call gvv input 1 toggle-main-frame_gvv-mod
python tools/rcon.py call gvv describe 1 gvv_main-frame-main 2
python tools/rcon.py screenshot gvv 1 main
```
