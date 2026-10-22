# AF Mod Loader API

Shared helpers for **Alchemy Factory** mods loaded by AF Mod Loader, so mods that touch the same part of the game coexist instead of overwriting each other. It is a regular mod that other mods depend on, and it includes a template for starting new mods.

Status: version 0.1.7, in development. Each piece's in-game status is in docs/api.md. The API stays at 0.x, and may change, until 1.0.

Unofficial fan project. Alchemy Factory belongs to its developers.

## For players

You only need this mod when another mod says it needs "AF Mod Loader API". Put the `af-modloader-api` folder in `<game folder>\mods`, next to that mod. AF Mod Loader must be installed.

### What it changes in the game

On its own, nothing you can see. When a mod uses it, the API can:

- **Add tabs to the TAB menu** (the screen with Player, World and Recognition) or to the V menu (the item catalog with Materials, Goods, Stats and Ledger), and **add a section to the V menu's item sheet**. They are added while the game runs, in memory. No game file is changed.
- **Turn on the in-game console**, only if a mod added a console command. The console opens with F10 or the key left of 1.
- It reads and writes nothing in your saves, makes no network connection, and writes no files. The only file it looks at is the optional `af-modloader-api.json` described below.

### About the console

The console is **Unreal Engine's full developer console**, not a small box for the commands of mods. Besides the commands that mods add, it accepts everything the engine does, and some of that can crash the game or change its settings. Only use commands you understand. Type `af.help` to see the commands the installed mods added.

If you do not want the console at all, create the file `<game folder>\mods\.data\af-modloader-api.json` with this content:

```json
{ "console": false }
```

Then the API never turns the console on, and the commands of mods cannot be used. If the file does not exist, the console is turned on when a mod needs it. `UE4SS.log` says whether the console was turned on and which mods asked for it.

## For mod authors

- [docs/api.md](docs/api.md): the API, with an example for every function and what has been verified in the game.
- [template/my-mod](template/my-mod): a starting point. Copy it, rename it, edit `scripts/main.lua`.
- [docs/tab-menu.md](docs/tab-menu.md), [docs/catalog-menu.md](docs/catalog-menu.md) and [docs/console.md](docs/console.md): how the game's TAB menu, V menu and console work, as verified in game.

```lua
local api = AF.require("af-modloader-api").use(AF)

api.tabs.add({
  id = "hello",
  title = "Hello",
  build = function(page)
    page:text("Hello from my mod")
  end,
})
```

### Development

Needs Lua 5.4, StyLua and Luacheck (see AGENTS.md). `lua scripts/check.lua` runs formatting, lint and the tests.

To try the mod in a game that already has AF Mod Loader installed, close the game and run `lua scripts/dev-install.lua` from the repository root. Add `--with-template` to also install the template mod, and `--remove-template` to remove it again. Pass the game folder as an argument, or set `AF_GAME_DIR`.

## License

MIT. See [LICENSE](LICENSE). The way the console is turned on follows UE4SS's ConsoleEnablerMod (MIT); its notice is in [docs/console.md](docs/console.md).
