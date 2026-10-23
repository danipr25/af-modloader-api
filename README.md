# AF Mod Loader API

A shared library mod for **Alchemy Factory** mods that run on [AF Mod Loader](https://github.com/danipr25/af-modloader). Mods use it to add tabs to the TAB menu and the V menu, add sections to the V menu's item sheet, and add console commands, without overwriting each other. It includes a template for new mods.

Unofficial fan project. Alchemy Factory belongs to its developers. Status: version 0.1.3. The API may change until 1.0. See the [changelog](CHANGELOG.md).

## Install

You only need it when a mod asks for it. AF Mod Loader must be installed first.

1. Close the game.
2. Download `af-modloader-api-<version>.zip` from [Releases](https://github.com/danipr25/af-modloader-api/releases).
3. Extract it into `<game>\mods`, so you get `<game>\mods\af-modloader-api\mod.json`.

To update, delete the old `<game>\mods\af-modloader-api` folder first, then extract the new zip. Data that mods keep in `<game>\mods\.data` stays.

Every release lists the SHA-256 of its files in `SHA256SUMS.txt`, and GitHub Actions builds the files and attests them. To check a download, run `Get-FileHash -Algorithm SHA256 <file>` and compare, or use the [GitHub CLI](https://cli.github.com/):

```
gh attestation verify <file> --repo danipr25/af-modloader-api --signer-workflow danipr25/af-modloader-api/.github/workflows/release.yml
```


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

### Releasing

Work reaches `development` by pull request, and CI (the `check` job, the same as `lua scripts/check.lua`) must pass. Only the owner publishes, and only from GitHub Actions: nothing is built or uploaded from a personal machine.

1. On `development`, set the new version (`mod/mod.json` and `VERSION` in `mod/scripts/main.lua`, which must match) and write its section in [CHANGELOG.md](CHANGELOG.md).
2. Open a pull request from `development` into `main` and merge it. `main` accepts nothing else.
3. Tag the merge commit `vX.Y.Z` (the version) on `main` and push the tag. The [release workflow](.github/workflows/release.yml) checks that the commit is on `main` and that the tag matches the code, runs the checks, builds the zip, attests it and publishes a GitHub release with the CHANGELOG section as notes.

To rehearse, run the Release workflow by hand from `main` ("Run workflow"): it does everything except the attestation and the release, and keeps the files and notes as a workflow artifact.

## License

MIT. See [LICENSE](LICENSE). The console code follows UE4SS's ConsoleEnablerMod (MIT); its notice is in [docs/console.md](docs/console.md).
