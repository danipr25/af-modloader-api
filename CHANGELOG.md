# Changelog

All notable changes to AF Mod Loader API. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). While the version is 0.x, a patch version fixes things or adds functions without breaking mods, and a minor version may break them and says how here.

## [0.1.2] - 2026-10-23

Additions:

- `page:divider(heading)`, `pane:divider(heading)` and `section:divider(heading)`: a horizontal divider, the game's own one, with an optional heading. If the game's divider is not available, a plain solid line is used.
- `row:divider()`: a vertical line between two things of a row (page, pane and list rows), with 16 of room on each side.
- `page:columns(widths, opts)`: `opts = { divider = true }` draws a vertical line between the panes.

Changes every mod gets (the look of the V menu changes, no code needs to):

- Pages of the V menu are padded more: left 40, top 36, right 24, bottom 16 (was 24, 20, 24, 16), so the first line clears the frame's corner ornament. The TAB menu is unchanged.
- Small buttons (`{ small = true }`) are drawn at 0.7 instead of 0.6, with 10 of room at each side of the label. Arrows are unchanged.
- The scroll boxes of `grid` and `list` use the game's scrollbar, and `input` uses the game's search box look. If the game's widgets cannot be found, the engine's default stays and one line is logged.

Verified in game in a probe (game 1.1.5024, UE4SS experimental, 2026-10-23): the game's divider with and without a heading, the vertical line, the scrollbar and search box style copies, the small button variant and the page padding. The same calls through the API 0.1.2 are not verified yet, nor is the column divider (its slot between panes was not tried) or typing in the styled search box.

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
