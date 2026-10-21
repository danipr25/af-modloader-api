# API reference

AF Mod Loader API 0.1.1 for mod authors. Game 1.1.5023, UE4SS 1181, AF Mod Loader 0.1.0.

Each function says what is **verified in game** and what is **not verified yet**. Nothing marked "not verified" has run in the game: it is written from the UE4SS and Unreal Engine documentation, wrapped so that a failure is logged instead of crashing, and waits for the in-game test. Verified findings are recorded in [tab-menu.md](tab-menu.md) and [console.md](console.md).

## Contracts

### Versions

The API is 0.x until 1.0. A patch version (0.1.1) fixes things or adds functions and never breaks a mod. A minor version (0.2.0) may break mods, and the changelog says how. So a mod depends on one minor line of the API, and of the loader, which follows the same rule:

```json
"depends": { "af-modloader": ">=0.1.0 <0.2.0", "af-modloader-api": ">=0.1.0 <0.2.0" }
```

`api.version` is the installed version as text, like `"0.1.1"`.

Raise the lower bound to the first version that has every call your mod uses. `page:row()`, `row:button`, `page:grid()` and clicks on tiles came with 0.1.1, so a mod that uses them depends on `"af-modloader-api": ">=0.1.1 <0.2.0"`. A mod that does not use them keeps working with `>=0.1.0`.

### Threads

`build`, `run` and `onChange` run on the game thread, so they may read and change game objects. Call `tab:refresh()` and the widget handles from the game thread too (hooks, console commands, `ExecuteInGameThread`).

### Handles and their lifetime

`page` and everything made from it (text, input, list, row, button, grid) are valid until the **next build of that page**, whether it comes from `tab:refresh()` or from the menu being created again. Keep a handle to change something later, for example `heading:set("...")`, but do not keep it across a refresh: use the new ones the next `build` receives.

A handle that is no longer valid does nothing, and writes one line to `UE4SS.log` the first time it is used. It never raises an error.

### Callbacks never crash the game

Every function a mod gives the API (`build`, `run`, `onChange`, click callbacks) runs in `pcall`. An error is written to `UE4SS.log` with the mod id and a stack trace. A `build` that fails leaves a page with the line "This page failed to load, see UE4SS.log". A command that fails answers "Command failed, see UE4SS.log" in the console.

### When to register

`tabs.add` and `console.add` work only while your mod's entrypoint (`scripts/main.lua`) runs, at its top level. Calls made after the API has sealed its registry (at the first game start, or the first time the TAB menu is built, which is after every entrypoint) raise an error that says so. This keeps the tab order fixed and lets the API decide about the console after every mod has registered.

### Restarting mods and re-entrancy

Removing the tabs when UE4SS restarts its mods ships disabled until it is verified in game (UE4SS may run unload code off the game thread). After a UE4SS mods restart the tabs stay inactive until a save is loaded again; the log says so ("load the save again or restart the game"). Titles that the game itself uses (Player, World, Recognition) cannot be used for a tab.

Calling `tab:refresh()` while a page is being built is ignored with a log line. Inside `onChange`, update the handles you already have (`text:set`, `list:clear()` and new rows), and do not call `refresh`.

### When the game's menu is not what we expect

If the TAB menu does not have the structure described in [tab-menu.md](tab-menu.md) (for example after a game patch), the API leaves the menu untouched, writes one line to `UE4SS.log` and your tabs do not appear. Nothing is added half way.

## Getting the API

```lua
local api = AF.require("af-modloader-api").use(AF)
```

`AF.require` needs `"af-modloader-api"` in your `mod.json` `depends`. `use(AF)` gives you a handle that remembers your mod id for logs and error messages. It raises a clear error if `AF` is missing or is not your mod's `AF` table. The handle and the shared API table are read-only.

## Tabs

### `api.tabs.add(spec)` returns `tab`

Adds a tab to the TAB menu (the screen with Player, World and Recognition).

```lua
local tab = api.tabs.add({
  id = "recipes",            -- 1 to 32 characters: a-z, 0-9, "-" and "_". Unique within your mod.
  title = "Cauldron Recipes", -- the tab button's text, 1 to 40 characters, unique among all mods
  build = function(page)      -- fills the page; runs again on tab:refresh()
    page:text("Hello")
  end,
})
```

Tabs appear after the game's own, in the order mods registered them (which follows the loader's load order). A duplicate id or title is refused with a log line naming both mods; you get a tab that does nothing so your mod keeps running. Invalid arguments raise an error.

Status: **verified in game** for one tab (2026-10-21, game 1.1.5023): the tab is added on the first open, the highlighted tab is right, reopening adds nothing, `refresh()` from a console command rebuilds the page, and after loading another save the new menu gets the tab once. The group's `PreConstruct` hook fires before `BP_OnActivated`, and the tab is added from it. Two tabs from two mods are **verified** too: each opens its own page and the game's pages stay right. After a UE4SS mods restart (Ctrl+R with `EnableHotReloadSystem = 1`) the old tabs stay but do nothing, the log says to load the save again, and after loading it the tabs work again, once each; no crash. Removal on restart stays disabled and **not verified**.

Known limit: the game's tab bar has a fixed width. Four tabs fit; with five (two mods with a tab each) the last button is pushed out of line. Not handled yet.

### `tab:refresh()`

Rebuilds the page now by running `build` again, if the page exists. If the menu has not been opened yet, nothing happens: `build` runs when the menu is first opened.

```lua
api.console.add({
  name = "recipes.reload",
  help = "Rebuilds the recipes tab.",
  run = function(args, out)
    tab:refresh()
    out("done")
  end,
})
```

Status: **not verified**.

## Page widgets

All of them are created inside `build(page)`. You never touch the game's UI classes.

### `page:text(str)` returns `text`

Adds a line of text. `text:set(str)` changes it.

```lua
local heading = page:text("Recipes")
heading:set("Recipes (3)")
```

Status: **verified in game** (a `TextBlock`).

### `page:input(spec)` returns `input`

Adds a text box. `spec` is optional: `hint` is the text shown while the box is empty, `onChange(text)` is called when the player changes the text. `input:get()` returns the text and `input:set(str)` replaces it (this does not call `onChange`).

```lua
local box = page:input({
  hint = "Search",
  onChange = function(text)
    results:set("Searching for " .. text)
  end,
})
```

How `onChange` works: while the TAB menu is open, the API reads each such box about every 150 ms and calls `onChange` once for each change, so it may arrive up to 150 ms late and intermediate texts can be skipped.

Status: the box, typing in it, `onChange` and the polling (with `LoopInGameThreadWithDelay`) are **verified in game** (2026-10-21). `hint` and `get` are **not verified**. If `onChange` does not work in game, it is removed before 0.1.0 is released and mods use a search button instead.

### `page:row()` returns `row`

Adds a horizontal row on the page itself: things placed side by side.

- `row:text(str)` adds text and returns a text handle (`:set`).
- `row:item(itemName, count)` adds the game's item tile, like in a list row.
- `row:button(label, onClick)` adds the game's button with `label` as its text and returns a button handle. `onClick()` is called when the player clicks it. `button:set(label)` changes the label.

```lua
local row = page:row()
row:button("Previous", function() showPage(current - 1) end)
row:button("Next", function() showPage(current + 1) end)
```

Buttons live in rows made with `page:row()`. List rows (`list:row()`) have no buttons.

Status: `HorizontalBox` and the button (`WBP_ButtonBase_C` created with `Create`, label with `SetButtonText`) are **verified in game** in a spike (2026-10-21, see [widgets.md](widgets.md)). The API's own `row:button` and the click routing are **not verified** until the in-game test of 0.1.1.

### `page:grid()` returns `grid`

Adds a grid of item tiles that fills the rest of the page, wraps like text and scrolls, like the Recognition page (4 tiles per row in the TAB menu).

- `grid:tile(itemName, spec)` adds a tile with the item's icon and the game's own tooltip. `itemName` is the item's name in the game's data. `spec` is optional: `onClick(itemName)` is called when the player clicks the tile. A tile without `onClick` is only shown. There is no count option: the game does not show a count on these tiles in the TAB menu. It returns nothing.
- `grid:clear()` removes every tile. Tiles made before the call stop working, and their clicks are no longer reported.

```lua
local grid = page:grid()
for _, name in ipairs({ "GentianNectar", "Wood" }) do
  grid:tile(name, { onClick = function(clicked) heading:set("You clicked " .. clicked) end })
end
```

A page that holds both a `grid` and a `list` is expected to split the height between them (not verified).

Status: the grid (`WrapBox` in a `ScrollBox` that fills the page, 48 tiles, scrolling and tooltips) and the tile (`WBP_RecipeItemTile_C` with `UpdateItemInfo`) are **verified in game** in a spike (2026-10-21). `grid:clear()` (`WrapBox:ClearChildren`) and the API's own `grid:tile` are **not verified**. The tile class may not be loaded when the game starts (not verified: the in-game test will tell), so the API finds it with `StaticFindObject` and falls back to `LoadAsset`; the log says which one worked. If the game loads the class again later, the API hooks it again (not verified).

### Clicks

A click calls your function on the game thread, inside `pcall`, like `build` (an error is logged with your mod id). The callback may call `tab:refresh()`, because a click is not a build, or change the handles it has (`text:set`, `grid:clear()` and new tiles).

Things to know:

- Tiles are expected to react when the mouse button goes **down**, and to any mouse button, so a right click should select too (expected from the hook, not verified).
- Clicks are only reported while the TAB menu is open. A click on a game tile or button the API did not create is ignored, with no log line.
- After a page is rebuilt, or the menu is created again (for example after loading a save), the old widgets are gone and their clicks are no longer reported. Use the new handles.
- The API registers one shared game hook for buttons and one for tiles, so several mods can use clicks without overwriting each other. The tile hook is registered when the first tile is made if the game has not loaded the tile class before.

Status: **not verified** until the in-game test of 0.1.1. The click hooks and the widgets they listen to are verified in the spike; that the hooks fire for every tile and button of the game is assumed from the spike's logs.

### `page:list()` returns `list`

Adds a scrolling list of rows.

- `list:clear()` removes every row. Rows made before the call stop working.
- `list:row()` adds a row and returns it.
- `row:text(str)` adds text to the row and returns a text handle (`:set`).
- `row:item(itemName, count)` adds the game's item tile for the item, with its icon and the game's own tooltip. `itemName` is the item's name in the game's data (for example `"GentianNectar"`), `count` defaults to 1.

```lua
local list = page:list()
local row = list:row()
row:text("Gentian Nectar x2 -> ")
row:item("GentianNectar", 2)
```

The API does not look up item names or recipes: that is the mod's job.

Status: the item tile (`WBP_SimpleItemTile_C` with `UpdateItemInfo`) is **verified in game** with a count of 1, including its tooltip. The scrolling list, its rows and the fill-the-page setting are **verified in game** too (2026-10-21): 300 rows of item tiles scroll smoothly, building them takes about 80 ms, and clearing and rebuilding the list on every filter change feels instant. How a count other than 1 is shown was not checked.

## Console

### `api.console.add(spec)` returns `true`, or `false` when refused

Adds a console command.

```lua
api.console.add({
  name = "recipes.unlockall",   -- lowercase <namespace>.<name>
  help = "Unlocks every recipe.",
  run = function(args, out)     -- args: list of plain strings. out(text): writes a line to the console.
    out("Unlocked " .. #args .. " recipes")
  end,
})
```

Rules for `name`:

- Only lowercase letters, digits, `.`, `_` and `-`.
- The form `<namespace>.<name>`, with a namespace of **at least 3 characters** (this avoids the short prefixes of the game's own console variables, like `r.` or `t.`; pick a namespace from your mod name).
- The `af.` namespace belongs to the API.
- A name already used by another mod is refused with a log line naming both mods.

The console is case-sensitive. Typing the all-uppercase form (`RECIPES.UNLOCKALL`) does not run the command: it answers "Commands are lowercase: type recipes.unlockall". Mixed case is not covered.

`args` holds the words after the command; double quotes group words (`recipes.find "gentian nectar"` is one argument). `out(text)` writes a line to the console only while `run` is executing. A later call goes to `UE4SS.log` with a note. A command that must ask for confirmation does that itself.

Status: **verified in game** (2026-10-21): commands with and without parameters, `af.help` and the uppercase answer. Output shows in the full console (press the key twice), not in the one-line bar.

### `af.help`

The API's own command. `af.help` lists every command with its mod and help text, and `af.help <name>` shows one. It does not make the API turn the console on.

### Turning the console on

Alchemy Factory ships without a developer console. When at least one mod (not counting the API) has added a command, the API turns it on once the game has started, and F10 or the key left of 1 opens it. Because it is Unreal's full developer console, it also accepts everything the engine does, not only the commands of mods: some of it can crash the game or change its settings.

A player who does not want that creates the file `<game folder>\mods\.data\af-modloader-api.json`:

```json
{ "console": false }
```

Then the console stays off, and commands from mods cannot be used. A missing file means "on". An unreadable file is ignored, which also means "on", and the log says why. `UE4SS.log` always states which mods asked for the console and whether it was turned on. See [console.md](console.md) for how it works.

Status: **verified in game** with a throwaway mod (the console opens with both keys). Verified with the API (2026-10-21): the console was turned on at the first game state (main menu) and worked after loading a save. The opt-out file `{ "console": false }` is verified too: the console stays closed and the log says why and how to turn it back on.

## Game hooks used

| Hook or object | Used for | Status |
|---|---|---|
| `WBP_PlayerGearPanel_C:BP_OnActivated` and `BP_OnDeactivated` | Add tabs when the TAB menu opens; start and stop the input polling | hookable, verified in game |
| `WBP_TagSwitcherGroup_C:PreConstruct` | Notice the tab bar being rebuilt by the game | hookable, verified in game |
| `TagSwithcer.TitleList`, `EntryPanel:ClearChildren()`, `EntryList:Empty()`, `PreConstruct(false)`, `WidgetSwitcher_0:AddChild()` | The tab mechanism | verified in game |
| `/Script/CommonUI.CommonButtonBase:HandleButtonClicked` | Clicks on buttons made by `row:button` (fires for every CommonUI button in the game; the API ignores the ones it did not create) | hookable and fires on a click, verified in a spike (2026-10-21) |
| `WBP_RecipeItemTile_C:OnMouseButtonDown` (path in [widgets.md](widgets.md)) | Clicks on tiles made by `grid:tile` (fires on press, for any mouse button, for every such tile in the game) | hookable and fires on a click, verified in a spike (2026-10-21); registered when the first tile is made |
| `WidgetBlueprintLibrary:Create`, `WBP_ButtonBase_C:SetButtonText`, `WBP_RecipeItemTile_C:UpdateItemInfo`, `WrapBox:AddChildToWrapBox` | Buttons, tiles and the grid | verified in a spike (2026-10-21) |
| `LoadAsset` | Loads a game class (the tile) that is not loaded yet | not verified (the spike created the tile after loading it this way, but the in-game test of 0.1.1 will tell whether it is needed) |
| `WrapBox:ClearChildren` | `grid:clear()` | not verified |
| `WidgetSwitcher:GetChildIndex`, `GetChildAt`, `GetActiveWidgetIndex`, `SetActiveWidgetIndex`, widget `RemoveFromParent` | Check where our pages are, keep the highlight, clean up | not verified |
| `FindAllOf`, `GetOuter` | Fallback lookup of the tab bar if the member names change | not verified |
| `/Script/Engine.PlayerController:ClientRestart` | Turn the console on | hook registers; firing not verified |
| `RegisterInitGameStatePostHook` | Second trigger to turn the console on | verified in game: it turned the console on at the main menu |
| `/Script/Engine.Console`, `GameViewport.ViewportConsole`, `InputSettings.ConsoleKeys` | The console | verified in game |
| `RegisterConsoleCommandGlobalHandler` | Commands | verified in game |
| `LoopInGameThreadWithDelay` and `CancelDelayedAction`, or `LoopAsync` | Poll inputs for `onChange` | `LoopInGameThreadWithDelay` verified in game; `CancelDelayedAction` not verified |
| `AF.onUnload` | Stops the input polling on unload. Removing our tabs is disabled (see "Restarting mods") | not verified (loader feature) |

## Credits

The way the console is turned on follows UE4SS's `ConsoleEnablerMod` (MIT, UE4SS-RE). The license notice is in `mod/scripts/console.lua`.
