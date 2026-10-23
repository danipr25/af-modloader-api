# AF Mod Loader API

A shared library mod for **Alchemy Factory** mods that run on [AF Mod Loader](https://github.com/danipr25/af-modloader). Mods use it to add tabs to the TAB menu and the V menu, add sections to the V menu's item sheet, and add console commands, without overwriting each other. It includes a template for new mods.

Unofficial fan project. Alchemy Factory belongs to its developers. Status: version 0.1.7. The API may change until 1.0.

## Install

You only need it when a mod asks for it. AF Mod Loader must be installed first.

1. Close the game.
2. Copy the `mod` folder to `<game>\mods` and rename the copy to `af-modloader-api`.

On its own it changes nothing in the game. It adds things only in memory while the game runs, never touches your saves and uses no network.

**Console.** If a mod adds a console command, the API turns on Unreal Engine's developer console: F10, or the key left of 1. That console also accepts every engine command, and some of those can crash the game, so only use commands you understand. `af.help` lists the commands mods added. To keep the console off, create `<game>\mods\.data\af-modloader-api.json` with `{ "console": false }`.

## Make a mod

Copy [template/my-mod](template/my-mod), rename it, change `id` and `name` in `mod.json`, and edit `scripts/main.lua`.

```lua
local api = AF.require("af-modloader-api").use(AF)

api.tabs.add({
  id = "hello",
  title = "Hello",
  menu = "catalog", -- the V menu; leave it out for the TAB menu
  build = function(page)
    page:text("Hello from my mod")
  end,
})
```

Reference: [docs/api.md](docs/api.md), with every function, an example and its in-game status. How the game's menus and console work: [TAB menu](docs/tab-menu.md), [V menu](docs/catalog-menu.md), [console](docs/console.md).

## Development

Needs Lua 5.4, StyLua 2.5.2 and Luacheck 1.2.0 on the PATH (how to install them is in the [AF Mod Loader README](https://github.com/danipr25/af-modloader#development)), and a game with AF Mod Loader installed for testing.

| Command | What it does |
|---|---|
| `lua scripts/check.lua` | Formatting, lint and tests. `--fix` applies the formatting. |
| `lua scripts/dev-install.lua` | Copies `mod` into `<game>\mods\af-modloader-api`. `--with-template` also installs the template, and `--remove-template` removes it. The game must be closed. |

The game folder defaults to the Steam one. Pass another as the first argument or set `AF_GAME_DIR`.

## License

MIT. See [LICENSE](LICENSE). The console code follows UE4SS's ConsoleEnablerMod (MIT); its notice is in [docs/console.md](docs/console.md).
