# API reference

AF Mod Loader API 0.1.6 for mod authors. Game 1.1.5024, UE4SS 1181, AF Mod Loader 0.1.0.

Each function says what is **verified in game** and what is **not verified yet**. Nothing marked "not verified" has run in the game: it is written from the UE4SS and Unreal Engine documentation, wrapped so that a failure is logged instead of crashing, and waits for the in-game test. Verified findings are recorded in [tab-menu.md](tab-menu.md) and [console.md](console.md).

## Contracts

### Versions

The API is 0.x until 1.0. A patch version (0.1.6) fixes things or adds functions and never breaks a mod. A minor version (0.2.0) may break mods, and the changelog says how. So a mod depends on one minor line of the API, and of the loader, which follows the same rule:

```json
"depends": { "af-modloader": ">=0.1.0 <0.2.0", "af-modloader-api": ">=0.1.0 <0.2.0" }
```

`api.version` is the installed version as text, like `"0.1.6"`.

Raise the lower bound to the first version that has every call your mod uses. `page:row()`, `row:button`, `page:grid()` and clicks on tiles came with 0.1.1, so a mod that uses them depends on `"af-modloader-api": ">=0.1.1 <0.2.0"`. A mod that does not use them keeps working with `>=0.1.0`. `api.world` came with 0.1.2, so a mod that uses it depends on `"af-modloader-api": ">=0.1.2 <0.2.0"`. `text:color`, `page:text(str, { wrap = true })` and `button:enable` came with 0.1.3, so a mod that uses them depends on `"af-modloader-api": ">=0.1.3 <0.2.0"`. `page:text(str, { size = "small" })`, `row:text(str, { size = "small" })`, `row:button(label, onClick, { small = true })` and `row:arrow` came with 0.1.5, so a mod that uses them depends on `"af-modloader-api": ">=0.1.5 <0.2.0"`. 0.1.5 also centers the contents of rows vertically, for every mod. `row:item(name, 1, { onClick = fn })`, a clickable item tile in a page row, came with 0.1.6, so a mod that uses it depends on `"af-modloader-api": ">=0.1.6 <0.2.0"`.

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

Paging: the game's tab bar has a fixed width. When the tabs do not all fit, the API shows as many whole tabs as fit with an arrow at each end, and a click on an arrow moves the view (next brings at least the next tab into view and fills the view; previous brings at least the previous tab into view and fills the view; any mouse button works; no wrap-around; an arrow that cannot move is grey and does nothing). Every tab is at least 128 wide and wider with a long title, so short titles fit more tabs. The bar has room for 564 without arrows: the game's three tabs take 410, so without paging only one more tab fits (up to 154 wide; a 128-wide tab such as "Recipes" fits). When paged, 428 is left for tabs (about 3 at a time). Nothing changes when they all fit. Only the TAB menu is affected. Status: **verified in game** with API 0.1.4 build a3d30e8, Cauldron Recipes and the template (five tabs; 2026-10-22, game 1.1.5024): as many tabs as fit, arrows under the panel frame, each click brings a new tab, grey at the ends, every visible tab opens its own page, the view stays when TAB is closed and opened many times, after loading the save again paging works on the new menu, and the other panels with tab bars are unchanged. **Not verified**: the cleanup after a UE4SS mods restart (no restart appears in the test logs). See [tab-menu.md](tab-menu.md).

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

### `page:text(str, opts)` returns `text`

Adds a line of text. `text:set(str)` changes it. `text:color(r, g, b, a)` changes its color: each value is a number from 0 to 1 (a value outside that range is clamped, anything that is not a number is an error, also on a handle whose page was rebuilt; only a handle made on a page that was already gone does nothing and checks nothing), and `a` is optional (default 1). The API builds the color for the game itself, so mods only pass numbers. Texts made by `row:text` and by list rows have `color` too.

`opts` is optional: `{ wrap = true }` makes a long line wrap at the panel's edge. Without it the line runs past the edge, as before. `opts` must be nil or a table whose `wrap` is a boolean, otherwise it is an error. On a page handle kept past its page, `page:text` does nothing and checks nothing. Wrapping is only offered for texts made by `page:text` (rows are horizontal, so wrapping there is not verified).

`size` is optional: `"normal"` (the default) or `"small"`, anything else is an error. A small text is drawn at 0.7 of its size, keeps its real layout size and, on a page, starts at the left edge. `size = "small"` cannot be combined with `wrap` (error): a small line must be short. `row:text(str, { size = "small" })` works the same in a row (and in a list row). The handle (`set`, `color`) is the same.

```lua
local heading = page:text("Recipes")
heading:set("Recipes (3)")
heading:color(1.0, 0.75, 0.2, 1.0) -- gold
page:text("A long explanation that should stay inside the panel.", { wrap = true })
page:text("Normal cauldron, 2752 recipes", { size = "small" })
```

Status: the text (a `TextBlock`) is **verified in game**. `color` (`SetColorAndOpacity`) and `wrap` (`SetAutoWrapText(true)`) are **verified in game** (2026-10-21, game 1.1.5023): first in a probe on texts already shown, then with API 0.1.3 and the template, set at build time (a gold page heading, a grey row text, a long page line that wraps at the panel's edge). Color on list texts is not verified (same widget class). Small text: a `TextBlock` inside a `ScaleBox` at 0.7 is **verified in game** in a probe (2026-10-22, game 1.1.5024, see [widgets.md](widgets.md)); left-aligning its slot on a page (`SetHorizontalAlignment` on the vertical box slot) and the `size` option through the API are **not verified**.

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
- `row:item(itemName, count, opts)` adds the game's item tile, like in a list row. `opts` is optional and only for rows of a page (API 0.1.6): `{ onClick = function(itemName) end }` makes the tile clickable. A clickable tile is the game's `WBP_RecipeItemTile_C`, the one `grid:tile` makes, so it shows no count: `count` must be nil or 1, otherwise it is an error. A click with any mouse button calls `onClick(itemName)`, like on a grid tile. `opts` must be nil or a table whose `onClick` is a function, otherwise it is an error. A list row (`list:row()`) has no clickable tiles and rejects `opts` with an error (before 0.1.6 a third argument was ignored there). Unknown keys in `opts` are ignored. After a click that rebuilds the row, a second quick click hits whatever tile is now in that place (not verified in game).
- `row:button(label, onClick, opts)` adds the game's button with `label` as its text and returns a button handle. `onClick()` is called when the player clicks it. `button:set(label)` changes the label. `button:enable(on)` enables (`true`) or disables (`false`) it: a disabled button is grey and ignores clicks. `on` must be a boolean, otherwise it is an error, also on a handle whose page was rebuilt; only a handle made on a page that was already gone does nothing and checks nothing. Buttons start enabled; call `enable(false)` right after adding the button to its row, and keep the handle to enable it again later. `opts` is optional: `{ small = true }` draws a smaller button (the game's button inside a `ScaleBox` at 0.6, same handle and clicks). `opts` must be nil or a table whose `small` is a boolean, otherwise it is an error.
- `row:arrow(direction, onClick)` adds a small arrow button, `direction` being `"previous"` (points left) or `"next"` (points right), anything else is an error. It is the game's button inside a `ScaleBox` at 0.6 with the game's gold arrow picture on top. The handle has only `enable(on)`: like `button:enable`, but the arrow is also grey when disabled and gold when enabled. If the picture cannot be found, the arrow is a small button labelled `<` or `>` and one line is logged.

Rows center their contents vertically (API 0.1.5): a text, an item tile, a button and an arrow in the same row share a middle line. This applies to page rows and list rows.

```lua
local row = page:row()
local previous = row:button("Previous", function() showPage(current - 1) end)
previous:enable(false) -- grey on the first page
row:button("Next", function() showPage(current + 1) end)

-- A compact pager: small arrows with a small text between them.
local pager = page:row()
local back = pager:arrow("previous", function() showPage(current - 1) end)
pager:text("1 / 5", { size = "small" })
local forward = pager:arrow("next", function() showPage(current + 1) end)
back:enable(false)

-- An item tile the player can click (a page row only).
local chosen = page:row()
chosen:item("Wood", 1, { onClick = function(name) heading:set("You clicked " .. name) end })
```

Buttons live in rows made with `page:row()`. List rows (`list:row()`) have no buttons. About three buttons fit in a row: a fourth runs past the panel.

Status: `HorizontalBox` and the button (`WBP_ButtonBase_C` created with `Create`, label with `SetButtonText`) are **verified in game** in a spike (2026-10-21, see [widgets.md](widgets.md)). The API's own `row:button`, with a click that calls `tab:refresh()`, is **verified in game** too (2026-10-21, API 0.1.1): one effect per click, also after many fast clicks. `enable` (`SetIsEnabled`) is **verified in game** in a probe (2026-10-21): the button turns grey and clicks do nothing. Also verified with API 0.1.3 and the template (2026-10-21): a button disabled at build time is grey and ignores clicks, stays grey after closing and reopening the TAB menu, and works again after another button calls `enable(true)`. The click router also skips a button its handle marked disabled, as a second guard. **Not verified through the API** (API 0.1.6): a clickable `row:item` (a `WBP_RecipeItemTile_C` inside the `HorizontalBox`: its size, frame and centering are unverified and may look different from the tiles of a list row; the click on it uses the same hook as the grid tiles, which is verified; a right click is expected to work too, not verified) and, from API 0.1.5, the centering of row children (`SetVerticalAlignment` on the `HorizontalBoxSlot` is verified in a probe, 2026-10-22), `{ small = true }` and `row:arrow`. The probe verified a `ScaleBox` at 0.6 around the game's button (looks smaller, clicks arrive as usual) and the arrow overlay (button, gold arrow picture, clicks arrive); the arrow picture's size (64 before scaling) is a guess, the in-game test checks it. Row text, button and arrow slots that the game refuses to center are logged once.

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

Status: the grid (`WrapBox` in a `ScrollBox` that fills the page, 48 tiles, scrolling and tooltips) and the tile (`WBP_RecipeItemTile_C` with `UpdateItemInfo`) are **verified in game** in a spike (2026-10-21). The API's own `grid:tile` and `grid:clear()` (`WrapBox:ClearChildren`), with a tile click that clears and refills the grid, are **verified in game** too (2026-10-21, API 0.1.1): the right tile is reported, one effect per click, also with fast double clicks. In game 1.1.5023 the tile class was already loaded when the API looked for it, before any cauldron panel was opened. The API still falls back to `LoadAsset` if it is not, and hooks the class again if the game ever loads it again; both paths are **not verified** (not needed so far).

### Clicks

A click calls your function on the game thread, inside `pcall`, like `build` (an error is logged with your mod id). The callback may call `tab:refresh()`, because a click is not a build, or change the handles it has (`text:set`, `grid:clear()` and new tiles).

Things to know:

- Tiles (`grid:tile`, and `row:item` with `onClick`) are expected to react when the mouse button goes **down**, and to any mouse button, so a right click should select too (expected from the hook, not verified).
- Clicks are only reported while the TAB menu is open. A click on a game tile or button the API did not create is ignored, with no log line.
- After a page is rebuilt, or the menu is created again (for example after loading a save), the old widgets are gone and their clicks are no longer reported. Use the new handles.
- The API registers one shared game hook for buttons and one for tiles, so several mods can use clicks without overwriting each other. The tile hook (also used by `row:item` with `onClick`) is registered when the first tile is made if the game has not loaded the tile class before.

Status: **verified in game** (2026-10-21, API 0.1.1): clicks on two different tiles and on a button reach the right callback once; clicking the game's own tiles and buttons (inventory, build menu, other TAB pages) has no effect on mods; clicks keep working after loading another save and after a UE4SS mods restart (Ctrl+R) followed by loading the save, with one effect per click.

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

## World

Which world (the player's playthrough, with its save slots) is loaded. The facts behind it are in [world.md](world.md).

### `api.world.onEnter(fn)`

Calls `fn(world)` each time a world is loaded and its name is known: loading a save, starting a new game, loading another slot of the same world. Like tabs and commands, it can only be called while your mod's entrypoint runs. Callbacks run on the game thread, in `pcall` (an error is logged with your mod id and does not stop the next callback), in registration order. `world` is a plain table that is yours to keep or change.

```lua
api.world.onEnter(function(world)
  AF.log("world " .. world.title .. " -> " .. world.key)
  -- load your per-world data here, from <AF.dataDir>\mymod-<world.key>.json
end)
```

### `api.world.current()` returns `world` or `nil`

A fresh copy of the current world, or `nil` at the main menu (and until a world is known). Safe to call at any time on the game thread, also from `build`.

### The `world` table

| Field | Meaning |
|---|---|
| `title` | `WorldTitleName` exactly as the game gives it (UTF-8), for example `Prueba_2609125624`. Show it to the player and store it inside your own data. |
| `key` | `title` made safe for a file name: letters, digits, `_` and `-` are kept, every other byte becomes `~XX` (uppercase hex), so the key is always plain ASCII (Lua's `io.open` cannot open other paths). Over 48 characters it becomes the first 48, `-`, and 8 hex digits of the FNV-1a hash of the full title. The same title always gives the same key. |
| `generation` | A whole number that is different for every enter, also when the same world is loaded again. |

NTFS ignores case, so two titles that differ only by case would share a file. Store `title` inside your file and compare it when you read it.

### Delayed work and the generation

There is no way to cancel `ExecuteWithDelay`. A mod that schedules work for later must remember the generation and check it when the work runs, because the player may have gone to the menu or loaded another world in between. Run the work on the game thread: `ExecuteWithDelay` calls its function off the game thread, so hop back with `ExecuteInGameThread`.

```lua
api.world.onEnter(function(world)
  local generation = world.generation
  ExecuteWithDelay(5000, function()
    ExecuteInGameThread(function()
      local now = api.world.current()
      if not now or now.generation ~= generation then
        return -- the world changed: this work is stale
      end
      -- safe to touch the world's game objects here (still check them with IsValid)
    end)
  end)
end)
```

### When `current()` changes

`current()` changes only inside the API's own `InitGameState` hook, so right after a load it can lag a moment behind the game, and during a load it may still report the old world. Put world work in `onEnter`, not in your own `RegisterInitGameStatePostHook`, and check game objects with `IsValid`.

After a UE4SS mods restart (Ctrl+R) the game does not start a new game state, so the API reads the loaded world once, about a second after it starts, and calls `onEnter` for it. A mod may also read `current()` when it needs it. The API never reports a world it could not read: at the main menu, or if the game's save state cannot be read, `current()` is `nil` and the log says why.

Status: reading the world at `InitGameState` (menu, load, new game, back to the menu, another world, non-ASCII titles) was **verified in a probe** (2026-10-21, game 1.1.5023, see [world.md](world.md)). The API's own `onEnter` and `current()` were **verified in game** with the template (2026-10-21). **Not verified** yet: the read after a mods restart, multiplayer, sandbox worlds, or the order of callbacks between mods.

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
| `WBP_TagSwitcher_C:OnMouseButtonDown` (path in [tab-menu.md](tab-menu.md)) | Clicks on the tab bar's arrows (fires for every tab button in the game, for any mouse button; the API ignores the ones it did not create) | hookable and fires once per click, verified in a probe (2026-10-22, game 1.1.5024); registered when the arrows are first made |
| `SetVisibility`, `ForceLayoutPrepass`, `GetDesiredSize`, slot `SetPadding` on the tab bar and its tabs; `Overlay:AddChildToOverlay`; `Image:SetBrushFromTexture` | Paging the tab bar | verified in game (2026-10-22, game 1.1.5024, API 0.1.4); hiding the arrows when the tabs fit again is not verified (`SetVisibility` on the arrows themselves) |
| `TagSwithcer.TitleList`, `EntryPanel:ClearChildren()`, `EntryList:Empty()`, `PreConstruct(false)`, `WidgetSwitcher_0:AddChild()` | The tab mechanism | verified in game |
| `/Script/CommonUI.CommonButtonBase:HandleButtonClicked` | Clicks on buttons made by `row:button` (fires for every CommonUI button in the game; the API ignores the ones it did not create) | hookable and fires on a click, verified in a spike (2026-10-21) |
| `WBP_RecipeItemTile_C:OnMouseButtonDown` (path in [widgets.md](widgets.md)) | Clicks on tiles made by `grid:tile` and by `row:item` with `onClick` (fires on press, for any mouse button, for every such tile in the game) | hookable and fires on a click, verified in a spike (2026-10-21); registered when the first tile is made |
| `WidgetBlueprintLibrary:Create`, `WBP_ButtonBase_C:SetButtonText`, `WBP_RecipeItemTile_C:UpdateItemInfo`, `WrapBox:AddChildToWrapBox` | Buttons, tiles and the grid | verified in a spike (2026-10-21) |
| `LoadAsset` | Loads a game class (the button, the tiles) or the arrow texture `T_UI_RightArrow` if it is not loaded yet | returns the texture when it is already loaded (probe, 2026-10-22); loading an asset that is not loaded yet is not verified (not needed so far) |
| `WrapBox:ClearChildren` | `grid:clear()` | verified in game (API 0.1.1) |
| `WBP_ButtonBase_C:SetIsEnabled` | `button:enable(on)` | verified in a probe (2026-10-21): grey, clicks ignored |
| `TextBlock:SetColorAndOpacity` | `text:color(r, g, b, a)` | verified on page and row texts (2026-10-21); list texts not verified |
| `ScaleBox` (`SetStretch(7)`, `SetUserSpecifiedScale`), `Overlay`, `Image:SetDesiredSizeOverride`, `Image:SetRenderScale` | Small text and buttons, arrow buttons (`row:arrow`) | `ScaleBox` and the arrow overlay verified in a probe (2026-10-22, game 1.1.5024); not verified through the API (API 0.1.5) |
| `HorizontalBoxSlot:SetVerticalAlignment(2)`, `VerticalBoxSlot:SetHorizontalAlignment(1)` | Centered rows (0.1.5), left-aligned small text on a page | the horizontal box slot is verified in a probe (2026-10-22); the vertical box slot call is not verified |
| `TextBlock:SetAutoWrapText` | `page:text(str, { wrap = true })` | verified in a probe (2026-10-21) |
| `WidgetSwitcher:GetChildIndex`, `GetChildAt`, `GetActiveWidgetIndex`, `SetActiveWidgetIndex`, widget `RemoveFromParent` | Check where our pages are, keep the highlight, clean up | not verified |
| `FindAllOf`, `GetOuter` | Fallback lookup of the tab bar if the member names change | not verified |
| `/Script/Engine.PlayerController:ClientRestart` | Turn the console on | hook registers; firing not verified |
| `RegisterInitGameStatePostHook` | Second trigger to turn the console on | verified in game: it turned the console on at the main menu |
| `/Script/Engine.Console`, `GameViewport.ViewportConsole`, `InputSettings.ConsoleKeys` | The console | verified in game |
| `RegisterConsoleCommandGlobalHandler` | Commands | verified in game |
| `RegisterInitGameStatePostHook` and `FindFirstOf("GameSaveLoadSubsystem")` fields `IsPreviewScene` and `WorldTitleName` (`NewGameName`, `IsStartup`, `IsSandbox`, `NetSession` are only logged) | `api.world`: which world is loaded | verified in game (probe and API 0.1.2 with the template, 2026-10-21, game 1.1.5023) |
| `ExecuteWithDelay` then `ExecuteInGameThread` | The read after install | verified in a probe (2026-10-21) |
| `LoopInGameThreadWithDelay` and `CancelDelayedAction`, or `LoopAsync` | Poll inputs for `onChange` | `LoopInGameThreadWithDelay` verified in game; `CancelDelayedAction` not verified |
| `AF.onUnload` | Stops the input polling on unload. Removing our tabs is disabled (see "Restarting mods") | not verified (loader feature) |

## Credits

The way the console is turned on follows UE4SS's `ConsoleEnablerMod` (MIT, UE4SS-RE). The license notice is in `mod/scripts/console.lua`.
