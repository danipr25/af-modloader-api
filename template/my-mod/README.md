# My Mod

A starting point for an **Alchemy Factory** mod. It needs AF Mod Loader and AF Mod Loader API.

What it does in the game:

- Adds a tab called "My Mod" to the TAB menu, with a gold heading, a wrapped line, a text box, a button that starts disabled and one that enables it, and a list holding one item. The tab also shows which world is loaded ("World: <name>", or "No world loaded" at the main menu).
- Adds the console command `mymod.hello`. Because of that, AF Mod Loader API turns on the in-game console (F10 or the key left of 1) unless the player opted out. See the API's README.

It changes nothing in your saves.

## Make your own mod

1. Copy this folder and give it a new name. Use plain letters and digits (no accents).
2. In `mod.json`, change `id`, `name`, `description` and `authors`.
3. Edit `scripts/main.lua`.
4. Put the folder in `<game folder>\mods`.

About `depends` in `mod.json`: `"af-modloader-api": ">=0.1.0 <0.2.0"` means "any 0.1.x version of the API from 0.1.0 on". Raise the lower bound to the first version that has every call your mod uses. While the API is 0.x, a new minor version (0.2.0) may break mods, and a patch version (0.1.1) only fixes or adds things.

Mod files are Lua. UE4SS runs them, so the mod can use anything UE4SS offers, but the API is the supported way to add tabs and commands.
