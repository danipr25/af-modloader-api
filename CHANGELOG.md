# Changelog

All notable changes to AF Mod Loader API. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). While the version is 0.x, a patch version fixes things or adds functions without breaking mods, and a minor version may break them and says how here.

## [0.1.0] - 2026-10-23

First public release.

- Tabs in the TAB menu and in the V menu (the item catalog), with paging when the TAB menu's bar is full, so several mods can add tabs without overwriting each other.
- Sections on the V menu's item sheet.
- Page widgets for tabs: text, rows with buttons, item tiles and arrows, grids of clickable tiles, and a search box.
- Console commands for mods. If a mod adds one, the API turns on the in-game developer console (F10); a setting turns it off.
- `api.world`: which world is loaded.
- A template for a new mod, in `template/my-mod`.
