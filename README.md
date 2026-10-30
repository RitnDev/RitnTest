# RitnTest

FR : Outil de développement (jamais publié) pour tester les mods Ritn dans le vrai jeu, piloté par RCON.  
EN : Development tool (never published) to test Ritn mods inside the real game, driven through RCON.

## ⚠ Sécurité / Security

FR : **Ne jamais installer RitnTest sur un serveur public ou une partie partagée.** Son interface exécute n'importe quel
code Lua dans le mod testé (`eval`) et envoie de faux évènements GUI au nom de n'importe quel joueur : un autre mod
pourrait s'en servir. À réserver à une partie de test locale, avec RCON limité à `127.0.0.1`.  
EN : **Never install RitnTest on a public server or a shared game.** Its interface runs any Lua code inside the tested
mod (`eval`) and sends fake GUI events on behalf of any player: another mod could use it. Keep it for a local test
game, with RCON limited to `127.0.0.1`.

FR : La ligne de chargement ci-dessous peut rester dans un mod publié : elle ne fait rien si RitnTest n'est pas installé.  
EN : The loading line below can stay in a published mod: it does nothing when RitnTest is not installed.

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

FR : Dossier de Factorio : option `--factorio <dossier>`, ou variable d'environnement `RITNTEST_FACTORIO`. L'adresse et le
mot de passe RCON sont lus dans son `config/config.ini`.  
EN : Factorio folder: `--factorio <folder>` option, or `RITNTEST_FACTORIO` environment variable. The RCON address and
password are read from its `config/config.ini`.

```
python tools/rcon.py call gvv ping
python tools/rcon.py call gvv input 1 toggle-main-frame_gvv-mod
python tools/rcon.py call gvv describe 1 gvv_main-frame-main 2
python tools/rcon.py screenshot gvv 1 main
```

## Avec une IA / With an AI

FR : Pour Claude Code, copier `skills/factorio-mod-ritntest/` dans `.claude/skills/` du projet (ou `~/.claude/skills/`) :
l'IA sait alors mettre en place RitnTest, tester le mod en jeu et lire les erreurs elle-même.  
EN : For Claude Code, copy `skills/factorio-mod-ritntest/` into the project `.claude/skills/` (or `~/.claude/skills/`):
the AI then knows how to set RitnTest up, test the mod in game and read the errors by itself.
