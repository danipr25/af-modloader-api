# API reference

AF Mod Loader API 0.1.2 for mod authors. Game 1.1.5024, UE4SS 1181, AF Mod Loader 0.1.0.

Each function says what is **verified in game** and what is **not verified yet**. Nothing marked "not verified" has run in the game: it is written from the UE4SS and Unreal Engine documentation, wrapped so that a failure is logged instead of crashing, and waits for the in-game test. Verified findings are recorded in [tab-menu.md](tab-menu.md), [catalog-menu.md](catalog-menu.md) and [console.md](console.md).

## Contracts

### Versions

The API is 0.x until 1.0. A patch version (0.1.1) fixes things or adds functions and never breaks a mod. A minor version (0.2.0) may break mods, and the changelog says how. So a mod depends on one minor line of the API, and of the loader, which follows the same rule:

```json
"depends": { "af-modloader": ">=0.1.0 <0.2.0", "af-modloader-api": ">=0.1.0 <0.2.0" }
```

`api.version` is the installed version as text, like `"0.1.0"`.

Raise the lower bound to the first version that has every call your mod uses. Every call in this reference is in 0.1.0, so `>=0.1.0 <0.2.0` is enough, except the ones that say "added in 0.1.1" (`page:columns`, `pane:clear`, and the `space` functions): a mod that uses one needs `>=0.1.1 <0.2.0`. The ones that say "added in 0.1.2" (the `divider` functions and the options of `page:columns`) need `>=0.1.2 <0.2.0`. Later patch versions will say which version added what. Development builds before the first public release were numbered 0.1.1 to 0.1.7; 0.1.0 is the first public release, and the in-game verification records below that name those build numbers stay as they were written.

### Threads

`build`, `run` and `onChange` run on the game thread, so they may read and change game objects. Call `tab:refresh()` and the widget handles from the game thread too (hooks, console commands, `ExecuteInGameThread`).

### Handles and their lifetime

`page` and everything made from it (text, input, list, row, button, grid) are valid until the **next build of that page**, whether it comes from `tab:refresh()` or from the menu being created again. Keep a handle to change something later, for example `heading:set("...")`, but do not keep it across a refresh: use the new ones the next `build` receives.

A handle that is no longer valid does nothing, and writes one line to `UE4SS.log` the first time it is used. It never raises an error.

### Callbacks never crash the game

Every function a mod gives the API (`build`, `run`, `onChange`, click callbacks) runs in `pcall`. An error is written to `UE4SS.log` with the mod id and a stack trace. A `build` that fails leaves a page with the line "This page failed to load, see UE4SS.log". A command that fails answers "Command failed, see UE4SS.log" in the console.

### When to register

`tabs.add`, `catalog.section` and `console.add` work only while your mod's entrypoint (`scripts/main.lua`) runs, at its top level. Calls made after the API has sealed its registry (at the first game start, or the first time the TAB menu or the V menu is built, which is after every entrypoint) raise an error that says so. This keeps the tab order fixed and lets the API decide about the console after every mod has registered.

### Restarting mods and re-entrancy

Removing the tabs when UE4SS restarts its mods ships disabled until it is verified in game (UE4SS may run unload code off the game thread). After a UE4SS mods restart the tabs stay inactive until a save is loaded again; the log says so ("load the save again or restart the game"). Titles that the game itself uses cannot be used for a tab: Player, World and Recognition in the TAB menu, Materials, Goods, Stats and Ledger in the V menu. A title is unique across both menus.

Calling `tab:refresh()` while a page is being built is ignored with a log line. Inside `onChange`, update the handles you already have (`text:set`, `list:clear()` and new rows), and do not call `refresh`.

### When the game's menu is not what we expect

If the TAB menu or the V menu does not have the structure described in [tab-menu.md](tab-menu.md) and [catalog-menu.md](catalog-menu.md) (for example after a game patch), the API leaves the menu untouched, writes one line to `UE4SS.log` and your tabs do not appear. Nothing is added half way. The same goes for the V menu's item sheet and sections.

## Getting the API

```lua
local api = AF.require("af-modloader-api").use(AF)
```

`AF.require` needs `"af-modloader-api"` in your `mod.json` `depends`. `use(AF)` gives you a handle that remembers your mod id for logs and error messages. It raises a clear error if `AF` is missing or is not your mod's `AF` table. The handle and the shared API table are read-only.

## Tabs

### `api.tabs.add(spec)` returns `tab`

Adds a tab to the TAB menu (the screen with Player, World and Recognition), or, with `menu = "catalog"`, to the V menu (the item catalog with Materials, Goods, Stats and Ledger).

```lua
local tab = api.tabs.add({
  id = "recipes",            -- 1 to 32 characters: a-z, 0-9, "-" and "_". Unique within your mod.
  title = "Cauldron Recipes", -- the tab button's text, 1 to 40 characters, unique among all mods and menus
  build = function(page)      -- fills the page; runs again on tab:refresh()
    page:text("Hello")
  end,
  menu = "tab",               -- optional: "tab" (the TAB menu, the default) or "catalog" (the V menu)
})
```

`menu` must be nil, `"tab"` or `"catalog"`, anything else is an error. The page widgets and the handle rules are the same in both menus. The tab id is unique within your mod across both menus.

**The V menu**: the tab is added after Materials, Goods, Stats and Ledger. Its pages are padded (left 40, top 36, right 24, bottom 16) so the text does not sit on the panel's frame or its corner ornament. There is no paging of the V menu's bar: with five tabs it fits, more are not handled. The panel class is not loaded when the game starts, so the API hooks the V menu when its class appears (see [catalog-menu.md](catalog-menu.md)); if that timing fails, the tab appears the next time the V menu opens. Status of the V menu's tabs: the mechanism (a title in `TitleList`, `PreConstruct`, a page in `SW_Main`) with one extra tab is **verified in game in a probe** (2026-10-22, game 1.1.5024); the API's own implementation, the highlighted tab after a rebuild (read from `CurrentActivePage`), the lazy hook registration are **not verified**. The padding values were picked by eye in a probe (2026-10-23, game 1.1.5024, API 0.1.1: with top 20 the first line sat under the frame's top-left ornament; top 36 and left 40 were chosen); the same values through the API 0.1.2 are **verified in game** (2026-10-23, game 1.1.5024, API 0.1.2 test build): the first line clears the frame's corner ornament. Two added tabs in this menu (Cauldron Recipes and a probe) are **verified in game** (2026-10-23, game 1.1.5024, API 0.1.1): each opens its own page.

Tabs appear after the game's own, in the order mods registered them (which follows the loader's load order). A duplicate id or title is refused with a log line naming both mods; you get a tab that does nothing so your mod keeps running. Invalid arguments raise an error.

Status of the TAB menu: **verified in game** for one tab (2026-10-21, game 1.1.5023): the tab is added on the first open, the highlighted tab is right, reopening adds nothing, `refresh()` from a console command rebuilds the page, and after loading another save the new menu gets the tab once. The group's `PreConstruct` hook fires before `BP_OnActivated`, and the tab is added from it. Two tabs from two mods are **verified** too: each opens its own page and the game's pages stay right. After a UE4SS mods restart (Ctrl+R with `EnableHotReloadSystem = 1`) the old tabs stay but do nothing, the log says to load the save again, and after loading it the tabs work again, once each; no crash. Removal on restart stays disabled and **not verified**.

Paging: the game's tab bar has a fixed width. When the tabs do not all fit, the API shows as many whole tabs as fit with an arrow at each end, and a click on an arrow moves the view (next brings at least the next tab into view and fills the view; previous brings at least the previous tab into view and fills the view; any mouse button works; no wrap-around; an arrow that cannot move is grey and does nothing). Every tab is at least 128 wide and wider with a long title, so short titles fit more tabs. The bar has room for 564 without arrows: the game's three tabs take 410, so without paging only one more tab fits (up to 154 wide; a 128-wide tab such as "Recipes" fits). When paged, 428 is left for tabs (about 3 at a time). Nothing changes when they all fit. Only the TAB menu is affected. Status: **verified in game** with API 0.1.4 build a3d30e8, Cauldron Recipes and the template (five tabs; 2026-10-22, game 1.1.5024): as many tabs as fit, arrows under the panel frame, each click brings a new tab, grey at the ends, every visible tab opens its own page, the view stays when TAB is closed and opened many times, after loading the save again paging works on the new menu, and the other panels with tab bars are unchanged. **Not verified**: the cleanup after a UE4SS mods restart (no restart appears in the test logs). See [tab-menu.md](tab-menu.md).

### `tab:refresh()`

Rebuilds the page now by running `build` again, if the page exists. If the menu has not been opened yet, nothing happens: `build` runs when the menu is first opened. Verified in game (2026-10-22, game 1.1.5024, API 0.1.5 and 0.1.6): `tab:refresh()` from a button click rebuilds the whole page and the whole menu flickers visibly for a moment, so for a small change update the handles in place (`text:set`), which does not flicker. A rebuild on a page step or a filter change in Cauldron Recipes was not noticeable.

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

### `tab:select()` returns `true` or `false`

Selects the tab, as if the player clicked it. Only for tabs of the V menu (`menu = "catalog"`), and only while the V menu is open: it returns `true` when the selection was scheduled, `false` when the V menu is closed, the tab is not in it, or the tab belongs to the TAB menu (not supported in this version: `OnEntryClick` from Lua is not verified there, and the paging could hide the tab). It does not open menus. The click itself is deferred to the game thread (`ExecuteInGameThread`), so it is safe to call from a click callback.

```lua
-- A button on the item sheet opens your tab.
section:row():button("Recipes", function()
  tab:select()
end, { small = true })
```

Status: `OnEntryClick(index)` on the V menu's tab bar, called from a button click through `ExecuteInGameThread`, is **verified in game in a probe** (2026-10-22, game 1.1.5024). The API's `select` is **not verified**.

## Item sheet sections

### `api.catalog.section(spec)` returns `true`, or `false` when refused

Adds a section to the item sheet of the V menu: the panel that shows an item, with "Used in Crafting" and the records. Register it in your entrypoint, like tabs.

```lua
api.catalog.section({
  id = "cauldron",                    -- 1 to 32 characters: a-z, 0-9, "-" and "_". Unique within your mod.
  build = function(section, itemName) -- runs after the game shows an item; itemName is its row name
    section:text("Cauldron: 3 recipes", { size = "small" })
    local row = section:row()
    row:button("Recipes", function() end, { small = true })
  end,
})
```

After every time the game shows an item (`UpdateContent`), the API clears your section on that sheet and runs `build` again for the new item. Materials and Goods are different sheets and each gets the section. A `build` that writes nothing leaves the section empty (it takes no room), which is how a mod shows nothing for an item it has nothing to say about. The section sits under "Used in Crafting", above the records, and is one box per mod.

`section` is a restricted page: `section:text(str, opts)` (the same `opts` and handle as `page:text`: `wrap` and `size`), `section:space(height)` (added in 0.1.1: empty vertical space, the same as `page:space`), `section:divider(heading)` (added in 0.1.2: the same as `page:divider`) and `section:row()` with `row:text` and `row:button` only (no items, arrows, inputs, lists or grids, and no `row:space`). Handles are valid until the next build of the section, which is the next item shown on that sheet: keep none across items. An error in `build` is logged with the mod id and the item, once with the stack trace and then in short, and the section stays empty. Clicks on section buttons work while the sheet is shown. A duplicate id is refused with a log line and `false`; invalid arguments raise an error.

Items shown before the API's hook exists have no section: the hook is registered when the V menu panel is first seen, and the first `UpdateContent` after that builds it.

Status: building a section under `Vtb_UsedIn:GetParent()` (a gold text and a row with a button) and its clicks are **verified in game in a probe** (2026-10-22, game 1.1.5024). **Not verified**: the API's implementation, clearing and rebuilding a section inside the `UpdateContent` hook, and `GetParent()` on the section's box. See [catalog-menu.md](catalog-menu.md).

## Page widgets

All of them are created inside `build(page)`. You never touch the game's UI classes.

### `page:text(str, opts)` returns `text`

Adds a line of text. `text:set(str)` changes it. `text:color(r, g, b, a)` changes its color: each value is a number from 0 to 1 (a value outside that range is clamped, anything that is not a number is an error, also on a handle whose page was rebuilt; only a handle made on a page that was already gone does nothing and checks nothing), and `a` is optional (default 1). The API builds the color for the game itself, so mods only pass numbers. Texts made by `row:text` and by list rows have `color` too.

`opts` is optional: `{ wrap = true }` makes a long line wrap at the panel's edge. Without it the line runs past the edge, as before. `opts` must be nil or a table whose `wrap` is a boolean, otherwise it is an error. On a page handle kept past its page, `page:text` does nothing and checks nothing. Wrapping is only offered for texts made by `page:text` (rows are horizontal, so wrapping there is not verified).

`size` is optional: `"normal"` (the default) or `"small"`, anything else is an error. A small text is drawn at 0.7 of its size, keeps its real layout size and, on a page, starts at the left edge. `size = "small"` cannot be combined with `wrap` (error): a small line must be short (the rejection itself is not verified in game). `row:text(str, { size = "small" })` works the same in a row (and in a list row). The handle (`set`, `color`) is the same.

```lua
local heading = page:text("Recipes")
heading:set("Recipes (3)")
heading:color(1.0, 0.75, 0.2, 1.0) -- gold
page:text("A long explanation that should stay inside the panel.", { wrap = true })
page:text("Normal cauldron, 2752 recipes", { size = "small" })
```

Status: the text (a `TextBlock`) is **verified in game**. `color` (`SetColorAndOpacity`) and `wrap` (`SetAutoWrapText(true)`) are **verified in game** (2026-10-21, game 1.1.5023): first in a probe on texts already shown, then with API 0.1.3 and the template, set at build time (a gold page heading, a grey row text, a long page line that wraps at the panel's edge). Color on list texts is not verified (same widget class). Small text: a `TextBlock` inside a `ScaleBox` at 0.7 is **verified in game** in a probe (2026-10-22, game 1.1.5024, see [widgets.md](widgets.md)); left-aligning its slot on a page (`SetHorizontalAlignment` on the vertical box slot) and the `size` option through the API are **verified in game** too (2026-10-22, game 1.1.5024, API 0.1.5 and 0.1.6): a small text shows smaller and starts at the left edge of a page.

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

The box uses the game's own search box look (added in 0.1.2): the API copies the `WidgetStyle` of `Edit_BlueprintSearch` in the build panel (`/Game/Blueprints/WBP/BuildOptionsPanel/WBP_BuildPanelNew`, the API loads that class first if it is not loaded yet, like the buttons) onto the new box before it is added to its parent. If the class or template cannot be found or the copy fails, the engine's default box is used and one line is logged (once, not on every rebuild). The style is only ever copied from the game's widget, never built from a Lua table (that crashed the game for fonts, see [widgets.md](widgets.md)).

How `onChange` works: while the TAB menu is open, the API reads each such box about every 150 ms and calls `onChange` once for each change, so it may arrive up to 150 ms late and intermediate texts can be skipped.

Status: the box, typing in it, `onChange` and the polling (with `LoopInGameThreadWithDelay`) are **verified in game** (2026-10-21). `hint` and `get` were verified later with the game style (see below). The style copy was verified in a probe (2026-10-23, game 1.1.5024, UE4SS experimental): the box shows the game's brown rounded look with a dark hint text and the game did not crash. Through the API 0.1.2 (2026-10-23, game 1.1.5024, API 0.1.2 test build) the hint, `set("abc")` then `get()` returning "abc", `onChange` once per typed change and `set("")` from a button are **verified in game** with that style. If `onChange` does not work in game, it is removed before 0.1.0 is released and mods use a search button instead.

### `page:row()` returns `row`

Adds a horizontal row on the page itself: things placed side by side.

- `row:text(str)` adds text and returns a text handle (`:set`).
- `row:item(itemName, count, opts)` adds the game's item tile, like in a list row. `opts` is optional and only for rows of a page: `{ onClick = function(itemName) end }` makes the tile clickable. A clickable tile is the game's `WBP_RecipeItemTile_C`, the one `grid:tile` makes, so it shows no count: `count` must be nil or 1, otherwise it is an error. A click with any mouse button calls `onClick(itemName)`, like on a grid tile. `opts` must be nil or a table whose `onClick` is a function, otherwise it is an error. A list row (`list:row()`) has no clickable tiles and rejects `opts` with an error. Unknown keys in `opts` are ignored. After a click that rebuilds the row, a second quick click hits whatever tile is now in that place: in game, a fast double click on one of two clickable tiles whose click rebuilds the row did not trigger the second tile (the interval is short), so there was one effect (2026-10-22, game 1.1.5024, API 0.1.5 and 0.1.6).
- `row:button(label, onClick, opts)` adds the game's button with `label` as its text and returns a button handle. `onClick()` is called when the player clicks it. `button:set(label)` changes the label. `button:enable(on)` enables (`true`) or disables (`false`) it: a disabled button is grey and ignores clicks. `on` must be a boolean, otherwise it is an error, also on a handle whose page was rebuilt; only a handle made on a page that was already gone does nothing and checks nothing. Buttons start enabled; call `enable(false)` right after adding the button to its row, and keep the handle to enable it again later. `opts` is optional: `{ small = true }` draws a smaller button (the game's button inside a `ScaleBox` at 0.7, with 16 of room at each side of its label, same handle and clicks; 0.6 and no extra room before 0.1.2). `opts` must be nil or a table whose `small` is a boolean, otherwise it is an error.
- `row:arrow(direction, onClick)` adds a small arrow button, `direction` being `"previous"` (points left) or `"next"` (points right), anything else is an error. It is the game's button inside a `ScaleBox` at 0.6 with the game's gold arrow picture on top. The handle has only `enable(on)`: like `button:enable`, but the arrow is also grey when disabled and gold when enabled. If the picture cannot be found, the arrow is a small button labelled `<` or `>` and one line is logged.

Rows center their contents vertically: a text, an item tile, a button and an arrow in the same row share a middle line. This applies to page rows and list rows.

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

- `row:space(width)` (added in 0.1.1) adds an empty gap of `width` between two things of the row. `width` must be a finite number above 0 and up to 400, otherwise it is an error. It works in page rows, pane rows and list rows (not in section rows).

```lua
local recipe = list:row()
recipe:item("Wood", 1)
recipe:text(" + ")
recipe:item("Stone", 1)
recipe:space(32) -- a gap before the next recipe in the same row
recipe:item("Coal", 1)
```

- `row:divider()` (added in 0.1.2) adds a vertical line between two things of the row, with 16 of room on each side. The line is 2 thick, spans the height of the row and has the color of the game's dividers. It works in page rows, pane rows and list rows (not in section rows). Takes no arguments.

```lua
local recipe = list:row()
recipe:item("Wood", 1)
recipe:text(" + ")
recipe:item("Stone", 1)
recipe:divider() -- a line instead of a gap between two recipes
recipe:item("Coal", 1)
```

Status of `row:divider()`: the widget (an `Image` with no texture, tinted with `SetColorAndOpacity` with the sRGB value of the game's divider art as is, `SetVisibility(3)`, inside a `SizeBox` with `SetWidthOverride(2.0)`, in a slot with vertical alignment Fill and two `Spacer` of 16) was **verified in a probe** (2026-10-23, game 1.1.5024, UE4SS experimental): it spans the row and reads as a subtle light line; three Advanced recipes per row fit in the two-thirds pane with lines between them. In the probe `SetDesiredSizeOverride` on the `Image` was ignored (lines about 40 thick), which is why the `SizeBox` is used. The API's own `row:divider()` is **verified in game** (2026-10-23, game 1.1.5024, API 0.1.2 test build) in list rows and pane rows, and three Advanced groups per row fit in the two-thirds pane with the page padding of 40.

Buttons live in rows made with `page:row()`. List rows (`list:row()`) have no buttons. About three buttons fit in a row: a fourth runs past the panel.

Small buttons in 0.1.2: scale 0.7 and `button.ContentBorder:SetPadding` left and right 16. A probe (2026-10-23, game 1.1.5024) picked 0.7 with 10 by eye; the API test then showed a long label ("Show advanced") filling its button, so the padding went up to 16, which looked right in game (2026-10-23, game 1.1.5024, API 0.1.2 test build). Arrows stay at 0.6.

Status: `HorizontalBox` and the button (`WBP_ButtonBase_C` created with `Create`, label with `SetButtonText`) are **verified in game** in a spike (2026-10-21, see [widgets.md](widgets.md)). The API's own `row:button`, with a click that calls `tab:refresh()`, is **verified in game** too (2026-10-21, dev build 0.1.1): one effect per click, also after many fast clicks. `enable` (`SetIsEnabled`) is **verified in game** in a probe (2026-10-21): the button turns grey and clicks do nothing. Also verified with API 0.1.3 and the template (2026-10-21): a button disabled at build time is grey and ignores clicks, stays grey after closing and reopening the TAB menu, and works again after another button calls `enable(true)`. The click router also skips a button its handle marked disabled, as a second guard. **Verified in game through the API** (2026-10-22, game 1.1.5024, API 0.1.5 and 0.1.6): a clickable `row:item` (a `WBP_RecipeItemTile_C` inside the `HorizontalBox`) shows correctly in a page row next to buttons and small text, and its click routes, also with a right click (any mouse button); the centering of row children (text, tiles, buttons and arrows share a middle line); `{ small = true }` buttons, which show smaller and click; and `row:arrow`: the gold arrow picture at size 64 (before scaling) looks right, it is grey when disabled, and clicks step pages. The probe before it verified a `ScaleBox` at 0.6 around the game's button and the arrow overlay. **Not verified**: the `<` and `>` fallback when the arrow texture is missing. Row text, button and arrow slots that the game refuses to center are logged once.

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

Its scrollbar is the game's (added in 0.1.2): see [Scrollbar](#scrollbar-of-grid-and-list).

A page that holds both a `grid` and a `list` is expected to split the height between them (not verified).

Status: the grid (`WrapBox` in a `ScrollBox` that fills the page, 48 tiles, scrolling and tooltips) and the tile (`WBP_RecipeItemTile_C` with `UpdateItemInfo`) are **verified in game** in a spike (2026-10-21). The API's own `grid:tile` and `grid:clear()` (`WrapBox:ClearChildren`), with a tile click that clears and refills the grid, are **verified in game** too (2026-10-21, dev build 0.1.1): the right tile is reported, one effect per click, also with fast double clicks. In game 1.1.5023 the tile class was already loaded when the API looked for it, before any cauldron panel was opened. The API still falls back to `LoadAsset` if it is not, and hooks the class again if the game ever loads it again; both paths are **not verified** (not needed so far).

### Clicks

A click calls your function on the game thread, inside `pcall`, like `build` (an error is logged with your mod id). The callback may call `tab:refresh()`, because a click is not a build, or change the handles it has (`text:set`, `grid:clear()` and new tiles).

Things to know:

- Tiles (`grid:tile`, and `row:item` with `onClick`) react when the mouse button goes **down**, and to any mouse button, so a right click selects too (verified in game for `row:item` with `onClick`, 2026-10-22, game 1.1.5024, API 0.1.5 and 0.1.6).
- Clicks are only reported while the TAB menu is open. A click on a game tile or button the API did not create is ignored, with no log line.
- After a page is rebuilt, or the menu is created again (for example after loading a save), the old widgets are gone and their clicks are no longer reported. Use the new handles.
- The API registers one shared game hook for buttons and one for tiles, so several mods can use clicks without overwriting each other. The tile hook (also used by `row:item` with `onClick`) is registered when the first tile is made if the game has not loaded the tile class before.

Status: **verified in game** (2026-10-21, dev build 0.1.1): clicks on two different tiles and on a button reach the right callback once; clicking the game's own tiles and buttons (inventory, build menu, other TAB pages) has no effect on mods; clicks keep working after loading another save and after a UE4SS mods restart (Ctrl+R) followed by loading the save, with one effect per click.

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

### Scrollbar of `grid` and `list`

Added in 0.1.2, nothing to call. The scroll boxes of `grid` and `list` (on pages, in panes and in the TAB menu) use the game's scrollbar instead of the engine's white one. The API copies `WidgetBarStyle` and `ScrollbarThickness` from `ScrollBox_40` of the item sheet class (`/Game/Blueprints/WBP/CatalogPanel/WBP_CatalogContent`, the API loads that class first if it is not loaded yet) onto the new `ScrollBox` before it is added to its parent. The order matters: copied after the box was added, only part of the style applied (a thin track without the frame). If the template is not found or the copy fails, the engine's scrollbar stays and one line is logged (once, not on every rebuild).

Status: the copy before adding was verified in a probe (2026-10-23, game 1.1.5024, UE4SS experimental): the game's scrollbar (frame and thumb, thickness 22) and no crash. Through the API 0.1.2 it is **verified in game** (2026-10-23, game 1.1.5024, API 0.1.2 test build) on a list and a grid, also in the Recipes tab (with the TAB menu opened before the V menu). Not verified: the scrollbar on a list or grid in the TAB menu itself.

### `page:divider(heading)`, `pane:divider(heading)` and `section:divider(heading)`

Added in 0.1.2. Adds a horizontal divider under what is already there: the game's own divider, the one the V menu draws between categories (two lines with diamond ends). `heading` is optional text shown in the middle of it, like `"Cauldron"`. Without a heading it is a plain line. Anything else (a number, an empty string...) is an error that points at your call. It returns nothing. On a page handle kept past its page it does nothing and checks nothing.

```lua
page:divider() -- a plain line
local left, right = table.unpack(page:columns({ 1, 2 }))
right:divider("Cauldron") -- a line with a heading
```

If the game's divider class is not available, a solid horizontal line (2 thick, the full width, the color of the game's dividers) is used instead, without the heading, and one line is logged per page. The heading text is drawn in the game's dark text color, as everything in the game's panels.

Status: the game's divider (`/Game/Blueprints/WBP/CatalogPanel/WBP_EntryDivider.WBP_EntryDivider_C`, made with `WidgetBlueprintLibrary:Create` like the buttons) was **verified in a probe** (2026-10-23, game 1.1.5024, UE4SS experimental) in a pane, with and without a heading: plain it measures 1020 x 16, with a heading 1133 x 44. The heading is set with `divider.ShowText = FText(heading)` and `divider.Txt_BuildOptionType:SetText(FText(heading))` together, before the divider is added (the verified combination); setting only the inner text was overwritten by the blueprint (it showed "Logistics"). A plain divider hides its text with `divider.Txt_BuildOptionType:SetVisibility(1)`. Through the API 0.1.2 (2026-10-23, game 1.1.5024, API 0.1.2 test build) `pane:divider()` (plain, in the narrow pane) and `pane:divider("Cauldron")` (with a heading) are **verified in game**, and so is `section:divider("Cauldron")` on the Goods item sheet. **Not verified**: the solid line fallback (the game's divider class was always available) and `page:divider`.

### `page:space(height)` and `pane:space(height)`

Added in 0.1.1. Adds empty vertical space of `height` below what is already there. `height` must be a finite number above 0 and up to 400, otherwise it is an error that points at your call (the check runs before anything is built). Item sheet sections have it too: `section:space(height)`.

```lua
page:text("Recipes")
page:space(12)
page:text("Normal cauldron")
```

Status: **verified in game** in the V menu (2026-10-23, game 1.1.5024, API 0.1.1, probe): `page:space` and `row:space` (in a page row and in list rows) show gaps. The widget is the game's UMG `Spacer` (`SetSize`). If the game refuses it, one line is written to `UE4SS.log` and the gap is missing; the test log had no such line. A gap of 32 between groups of item tiles does not visually separate them. `section:space` is verified too: the gap shows above the section text on the Goods item sheet and stays when switching items. Not tested in the TAB menu.

### `page:columns(widths, opts)` returns `{ pane, pane, ... }`

Added in 0.1.1 (`opts` in 0.1.2). Splits the rest of the page into panes side by side and returns one pane per entry of `widths`. The widths are relative: `{ 1, 2 }` is a third and two thirds. `widths` must be an array of 2 or more finite numbers above 0 (no upper limit on the count), otherwise it is an error that points at your call, before anything is built. There is a fixed gap of 24 between panes (verified in game to look right in the V menu).

`opts` is optional (0.1.2): `{ divider = true }` (as in `page:columns({ 1, 2 }, { divider = true })`) draws a vertical line between the panes, in a slot of its own, the full height of the columns, with the gap split as 12 on each side of it. `opts` must be nil or a table whose `divider` is nil or a boolean, and unknown keys are an error that points at your call (checked before anything is built). Without `opts`, or with `divider = false`, the columns are exactly as before.

```lua
local left, right = table.unpack(page:columns({ 1, 2 }))
local box = left:input({ hint = "Search" })
local items = left:grid()
items:tile("Wood", {
  onClick = function(name)
    right:clear() -- rebuild only the right pane, the left one keeps its scroll
    right:text(name)
    right:space(12)
    right:list():row():item(name, 1)
  end,
})
```

A pane has the same `text`, `input`, `row`, `list`, `grid`, `space` and `divider` as the page, with the same options and handles, plus `clear`. There is no `columns` inside a pane. A `grid` or `list` in a pane fills the rest of that pane and scrolls on its own. A pane's rows have `row:space`.

The columns take the rest of the page's height, like a grid or a list. Anything added to the page after `columns` sits below them, at the bottom of the page, and a second widget that also fills (a grid or list on the page) shares the height with them.

On a page handle kept past its page, `columns` still checks `widths` and then returns inert panes: every method does nothing.

Status: **verified in game** in the V menu (2026-10-23, game 1.1.5024, API 0.1.1, probe). `columns({ 1, 2 })` shows two panes at a third and two thirds with the 24 gap; a `grid` in the narrow pane shows 4 tiles per row; the grid and a list scroll independently in their panes; an input in a pane fires `onChange`; clicks route in both panes, also after `tab:refresh()` rebuilt the page; small text in a pane is left-aligned. The log had no "could not" line for the slot calls. Content wider than its pane is cut silently at the pane's edge (the scroll box clips it): in the two-thirds pane a list row of three groups of 3 tiles joined by " + " lost its third group, and one group of 3 tiles with 2 " + " texts takes about a third of that pane. **Not verified**: `columns` in the TAB menu (only the V menu was tested), and the `divider` option: the line itself was verified in rows in a probe (see `row:divider()`), but its slot between panes (Auto size, vertical alignment Fill, padding 12) was not tried, so how it looks was **not verified** in the probe. Through the API 0.1.2 (2026-10-23, game 1.1.5024, API 0.1.2 test build) `page:columns({ 1, 2 }, { divider = true })` is **verified in game** in the V menu: the line shows between the panes. Not verified in the TAB menu.

### `pane:clear()`

Added in 0.1.1. Removes everything in that pane and nothing else, so a mod can rebuild one pane on a click without calling `tab:refresh()`: no flicker, and the other pane keeps its scroll and state.

After `clear`, the handles made in that pane before (texts, inputs, rows, lists, grids) are dead: they do nothing and write one line to `UE4SS.log` the first time, like handles after a refresh. Their click callbacks are dropped, and the pane's inputs stop calling `onChange`. Use the handles you make after `clear`. The other pane and the page are not affected. `clear` on a pane whose page was rebuilt does nothing.

It is made to be called from a click callback of a tile or button in the same pane (the example above): the click router has already picked the callback when it runs, so dropping the clicked widget's own entry is safe.

Status: **verified in game** in the V menu for the case the probe exercised (2026-10-23, game 1.1.5024, API 0.1.1): a click on a tile in the left pane called `right:clear()` and rebuilt the right pane with no flicker, many times in a row and on the same tile repeatedly; the left grid kept its scroll; the arrows and the button of the rebuilt pane routed clicks. **Not verified**: clearing a pane from a click on a tile inside that same pane (the probe only cleared the right pane from left-pane tiles, and its right-pane arrows and button did not clear). The log had no "pane:clear failed" line.

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
| `WBP_CatalogPanel_C:BP_OnActivated` and `BP_OnDeactivated` (`/Game/Blueprints/WBP/CatalogPanel/`) | Add tabs when the V menu opens; start and stop the input polling | `BP_OnActivated` hookable and fires on every open, verified in a probe (2026-10-22, game 1.1.5024); registered when the class appears (it is not loaded at start), that registration is not verified |
| `WBP_TagSwitcherGroup_C:PreConstruct` | Notice the tab bar being rebuilt by the game; also tells the API that the V menu's class exists | hookable, verified in game; firing for the V menu's group is not verified |
| `WBP_CatalogContent_C:UpdateContent` | Rebuild the item sheet sections for the item shown | fires for every item shown, `ConfigName.ConfigName` is the item, verified in a probe (2026-10-22, game 1.1.5024) |
| `WBP_CatalogContent_C` members `Vtb_UsedIn` (its `GetParent()`) and `WidgetTree`; `VerticalBox:AddChildToVerticalBox`, `ClearChildren` | The section's place and rebuild | appending under `Vtb_UsedIn:GetParent()` verified in a probe; `ClearChildren` of a section and `GetParent()` of our box not verified |
| `WBP_CatalogPanel_C` members `WBP_TagSwitcherGroup`, `SW_Main`, `CurrentActivePage`; `WidgetSwitcherSlot:SetPadding`; `IsActivated` | The V menu's tab mechanism, padding of the pages, the highlighted tab, "is the menu open" | members and the mechanism verified in a probe (`CurrentActivePage` not fully); `SetPadding` and `IsActivated` not verified |
| `WBP_CatalogPanel_C` bound `OnTagSwitch` event (name in [catalog-menu.md](catalog-menu.md)) | Safety net: makes sure the V menu shows the page of the clicked mod tab (`SW_Main:GetActiveWidget`, `SetActiveWidget`) | the event fires on every tab click, verified in a probe; the safety net itself is not verified |
| `WBP_TagSwitcherGroup_C:OnEntryClick(index)` | `tab:select()` | verified in a probe from a button click through `ExecuteInGameThread` (2026-10-22, game 1.1.5024) |
| `WBP_TagSwitcher_C:OnMouseButtonDown` (path in [tab-menu.md](tab-menu.md)) | Clicks on the tab bar's arrows (fires for every tab button in the game, for any mouse button; the API ignores the ones it did not create) | hookable and fires once per click, verified in a probe (2026-10-22, game 1.1.5024); registered when the arrows are first made |
| `SetVisibility`, `ForceLayoutPrepass`, `GetDesiredSize`, slot `SetPadding` on the tab bar and its tabs; `Overlay:AddChildToOverlay`; `Image:SetBrushFromTexture` | Paging the tab bar | verified in game (2026-10-22, game 1.1.5024, API 0.1.4); hiding the arrows when the tabs fit again is not verified (`SetVisibility` on the arrows themselves) |
| `TagSwithcer.TitleList`, `EntryPanel:ClearChildren()`, `EntryList:Empty()`, `PreConstruct(false)`, `WidgetSwitcher_0:AddChild()` | The tab mechanism | verified in game |
| `/Script/CommonUI.CommonButtonBase:HandleButtonClicked` | Clicks on buttons made by `row:button` (fires for every CommonUI button in the game; the API ignores the ones it did not create) | hookable and fires on a click, verified in a spike (2026-10-21) |
| `WBP_RecipeItemTile_C:OnMouseButtonDown` (path in [widgets.md](widgets.md)) | Clicks on tiles made by `grid:tile` and by `row:item` with `onClick` (fires on press, for any mouse button, for every such tile in the game) | hookable and fires on a click, verified in a spike (2026-10-21); registered when the first tile is made |
| `WidgetBlueprintLibrary:Create`, `WBP_ButtonBase_C:SetButtonText`, `WBP_RecipeItemTile_C:UpdateItemInfo`, `WrapBox:AddChildToWrapBox` | Buttons, tiles and the grid | verified in a spike (2026-10-21) |
| `LoadAsset` | Loads a game class (the button, the tiles) or the arrow texture `T_UI_RightArrow` if it is not loaded yet | returns the texture when it is already loaded (probe, 2026-10-22; the arrows through the API, 2026-10-22, API 0.1.5); loading an asset that is not loaded yet is not verified (not needed so far) |
| `WrapBox:ClearChildren` | `grid:clear()` | verified in game (dev build 0.1.1) |
| `WBP_ButtonBase_C:SetIsEnabled` | `button:enable(on)` | verified in a probe (2026-10-21): grey, clicks ignored |
| `TextBlock:SetColorAndOpacity` | `text:color(r, g, b, a)` | verified on page and row texts (2026-10-21); list texts not verified |
| `ScaleBox` (`SetStretch(7)`, `SetUserSpecifiedScale`), `Overlay`, `Image:SetDesiredSizeOverride`, `Image:SetRenderScale` | Small text and buttons, arrow buttons (`row:arrow`) | `ScaleBox` and the arrow overlay verified in a probe and through the API (2026-10-22, game 1.1.5024, API 0.1.5) |
| `HorizontalBoxSlot:SetVerticalAlignment(2)`, `VerticalBoxSlot:SetHorizontalAlignment(1)` | Centered rows, left-aligned small text on a page | the horizontal box slot is verified in a probe (2026-10-22); the vertical box slot call is verified through the API (2026-10-22, game 1.1.5024, API 0.1.5): small text starts at the left edge |
| `HorizontalBoxSlot:SetSize` (Fill) and `SetPadding`, `VerticalBox:ClearChildren` (a pane) | `page:columns`: the panes' widths and gap, and `pane:clear()` | verified in game in the V menu (2026-10-23, game 1.1.5024, API 0.1.1); `ClearChildren` from the click of a tile in the same pane not verified |
| `Spacer:SetSize` (`/Script/UMG.Spacer`) | `page:space`, `pane:space`, `row:space`, `section:space` | verified in game in the V menu (2026-10-23, game 1.1.5024, API 0.1.1) |
| `WBP_EntryDivider_C` (made with `Create`; `ShowText`, `Txt_BuildOptionType:SetVisibility`) | `page:divider`, `pane:divider`, `section:divider` | verified in a probe and through the API 0.1.2 (2026-10-23, game 1.1.5024); the solid line fallback is not verified |
| `Image` with no texture inside a `SizeBox` (`SetWidthOverride`, `SetHeightOverride`), `Image:SetColorAndOpacity`, `SetVisibility(3)` | `row:divider`, the solid line fallback, the column divider | vertical line verified in a probe and through the API 0.1.2 (`row:divider`, column divider in the V menu; 2026-10-23, game 1.1.5024); horizontal fallback not verified |
| `ScrollBox.WidgetBarStyle` and `ScrollbarThickness` copied from `WBP_CatalogContent_C:WidgetTree.ScrollBox_40`; `EditableTextBox.WidgetStyle` copied from `WBP_BuildPanelNew_C:WidgetTree.Edit_BlueprintSearch` | The game's scrollbar and search box look | copy before adding verified in a probe and through the API 0.1.2 (2026-10-23, game 1.1.5024, no crash; the search box with typing, `get`, `set` and `onChange`) |
| `button.ContentBorder:SetPadding` | Room around the label of small buttons | verified in a probe and through the API 0.1.2 (2026-10-23, game 1.1.5024; padding 16 looked right) |
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
