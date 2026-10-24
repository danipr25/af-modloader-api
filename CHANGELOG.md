# Changelog

All notable changes to AF Mod Loader API. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). While the version is 0.x, a patch version fixes things or adds functions without breaking mods, and a minor version may break them and says how here.

## [0.1.4] - 2026-10-24

Additions:

- `api.panels.tab(spec)`: side tabs on the game's cauldron panel, styled like the vertical tabs of the Z panel (Research / Upgrade). The tab's page uses the same widgets as the menu tabs (`text`, `input` with `onChange`, `list`, `row`, `button`, `divider`...), starts with dark text because the panel is light, and gets `info` with the cauldron (`actor`, `kind` = `"normal"` or `"advanced"`, `component`), `info.showGame()` and `info.isCurrent()`. The returned handle has `refresh()`. See [api.md](docs/api.md).
- `row:item(name, count, { scale = 0.6 })`: the optional `scale` draws the item tile smaller or larger (a ScaleBox, above 0 and up to 2), in page rows and list rows. `row:item` now also loads the game's tile class itself if no menu has been opened yet, and shows the row without the tile (one log line) if the class cannot be found.
- `api.defer(fn)`: runs a function on the game thread later, out of the caller (a click callback, for example). Errors are logged with the mod id.

Inside the API: pages shown on a game panel can start their texts in a given color (used by the cauldron panel only). Nothing else changes for existing mods.

Verified in game (1.1.5024, 2026-10-24) in a probe: the panel's structure and hooks, the tab layout, a page with a search box and a scrolling list, clicks, resetting on open and close. Two crashes found in the probe are avoided here: a game array is never walked with `ipairs`, and no game object is touched off the game thread (the input polling is a game-thread loop that stops when the panel closes or the world changes). Not verified: the tab tint (`SetBrushColor`) and the tab text's Fill alignment, the API's own implementation in game, the Advanced cauldron panel with the tabs, and multiplayer.

## [0.1.3] - 2026-10-24

Additions:

- `row:mark(label, onClick)` on list rows: a small clickable text, for a star or a similar toggle. It returns a text handle (`set`, `color`), so the label changes in place. It reacts to any mouse button, on press. It is centered vertically in the row, drawn at 0.6 and 40 wide before that scale. It exists only on list rows. Verified in game (1.1.5024) with Cauldron Recipes 0.1.3: the stars draw, fit three Advanced recipes per row and toggle in every column.
- `list:clear()` now also forgets the clicks of the marks of its rows.

Inside the API (no mod code needs to change): the tab bar arrows and the marks share one hook on `WBP_TagSwitcher_C:OnMouseButtonDown` per menu, registered when the first arrow or mark is made. The arrows after this change are not verified in game yet (they only show when the tabs do not fit).

Verified in game in a probe (game 1.1.5024, 2026-10-23): the tab widget as an invisible click target with a label on top, the star glyphs in the game's font, and three Advanced recipes plus their marks fitting in the two-thirds pane. Not verified: `row:mark` through the API in game, clicks in the second and third column, and the tab bar arrows after the hook change.

## [0.1.2] - 2026-10-23

Additions:

- `page:divider(heading)`, `pane:divider(heading)` and `section:divider(heading)`: a horizontal divider, the game's own one, with an optional heading. If the game's divider is not available, a plain solid line is used.
- `row:divider()`: a vertical line between two things of a row (page, pane and list rows), with 16 of room on each side.
- `page:columns(widths, opts)`: `opts = { divider = true }` draws a vertical line between the panes.

Changes every mod gets (the look of the V menu changes, no code needs to):

- Pages of the V menu are padded more: left 40, top 36, right 24, bottom 16 (was 24, 20, 24, 16), so the first line clears the frame's corner ornament. The TAB menu is unchanged.
- Small buttons (`{ small = true }`) are drawn at 0.7 instead of 0.6, with 16 of room at each side of the label. Arrows are unchanged.
- The scroll boxes of `grid` and `list` use the game's scrollbar, and `input` uses the game's search box look. If the game's widgets cannot be found, the engine's default stays and one line is logged.

Verified in game in a probe (game 1.1.5024, UE4SS experimental, 2026-10-23): the game's divider with and without a heading, the vertical line, the scrollbar and search box style copies, the small button variant and the page padding. The same calls through the API 0.1.2 were then verified in game (2026-10-23, game 1.1.5024, API 0.1.2 test build): page padding, the column divider, `pane:divider` with and without a heading, `row:divider` in list and pane rows, `section:divider`, the game's scrollbar and search box (typing, `get`, `set`, `onChange`) and the small buttons (padding raised to 16). Not verified: the `LoadAsset` fallback when a class is not loaded, `ShowText` alone, and the column divider in the TAB menu.

## [0.1.1] - 2026-10-23

- `page:columns(widths)`: split the rest of a page into side-by-side panes with relative widths. A pane has the same text, input, row, list, grid and space as the page.
- `pane:clear()`: rebuild one pane without rebuilding the page, also from a click inside that pane.
- `page:space(height)`, `pane:space(height)`, `row:space(width)` and `section:space(height)`: empty space.

Verified in game in the V menu (game 1.1.5024): columns, `pane:clear()` from clicks in another pane, and the spaces. Not verified: `pane:clear()` from a click inside the same pane, and columns and spaces in the TAB menu.

## [0.1.0] - 2026-10-23

First public release.

- Tabs in the TAB menu and in the V menu (the item catalog), with paging when the TAB menu's bar is full, so several mods can add tabs without overwriting each other.
- Sections on the V menu's item sheet.
- Page widgets for tabs: text, rows with buttons, item tiles and arrows, grids of clickable tiles, and a search box.
- Console commands for mods. If a mod adds one, the API turns on the in-game developer console (F10); a setting turns it off.
- `api.world`: which world is loaded.
- A template for a new mod, in `template/my-mod`.
