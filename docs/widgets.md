# Game widgets for pages

Widgets a page can use besides plain UMG text and boxes, and how a click reaches Lua. Game 1.1.5023, UE4SS 1181, verified in game on 2026-10-21 with a throwaway mod on a tab added by the API. Signatures come from the FModel export and the UE4SS header dump.

## A grid of item tiles

A `WrapBox` (`/Script/UMG.WrapBox`, created with `StaticConstructObject` and outer `panel.WidgetTree`) inside a `ScrollBox` whose slot fills the page lays tiles out in rows, like the Recognition page, and scrolls. `AddChildToWrapBox(tile)` adds a tile. In the TAB menu it gave 4 tiles per row.

## Item tile that can be clicked: `WBP_RecipeItemTile_C`

- Path: `/Game/Blueprints/WBP/Utility/WBP_RecipeItemTile.WBP_RecipeItemTile_C`. Parent class `BeltTDUserWidget`. Created with `WidgetBlueprintLibrary:Create(panel, class, playerController)`.
- `UpdateItemInfo(FName ConfigName, int32 ItemCount, double ProducePr, double ProduceSpeed, bool ForceRefresh, bool ShowPrDown, bool IconSmall)`: called as `(FName(item), count, 0.0, 0.0, true, false, false)` it shows the item icon, and hovering shows the game's item card (name and buying price).
- Clicking it calls its `OnMouseButtonDown`. A post hook on `WBP_RecipeItemTile_C:OnMouseButtonDown` receives the tile as the context, so the clicked tile is known by comparing addresses. With its `ClickEvent` property left at `false` (the default), the game does nothing else on the click.
- The hook fires for every `WBP_RecipeItemTile_C` in the game, so the handler must ignore tiles it did not create.

`WBP_SimpleItemTile_C` (used by the API's `row:item` without `onClick`, and by list rows) has no click function. With `onClick`, a page row's `row:item` uses `WBP_RecipeItemTile_C` instead (its look inside a `HorizontalBox` is verified in game with the API 0.1.6 development build, 2026-10-22, game 1.1.5024).

## Buttons

### `WBP_ButtonBase_C`

- Path: `/Game/Blueprints/WBP/Utility/WBP_ButtonBase.WBP_ButtonBase_C`. Parent chain `LyraButtonBase` (game) then `CommonButtonBase` (CommonUI). Created with `Create`. The game's teal button with a text label.
- `SetButtonText(FText)` (from `LyraButtonBase`) sets the label.
- A click calls `/Script/CommonUI.CommonButtonBase:HandleButtonPressed` and then `HandleButtonClicked`; post hooks on both receive the button as the context. `BP_OnClicked` never fired.
- These hooks fire for every CommonUI button in the game: the handler must ignore buttons it did not create.
- `SetIsEnabled(false)`: the button turns grey and clicks do nothing (`HandleButtonClicked` does not fire). `SetIsInteractionEnabled(false)` looks and acts the same. The API uses `SetIsEnabled`.
- Not used: `SetIsSelectable(true)` with `SetIsSelected(true, false)` draws a flat white box outside the game's style, and clicks still fire. `SetIsLocked(true)` changes nothing visible, and clicks still fire.
- About three of these buttons fit in a row: a fourth runs past the panel.

### The tab widget as a button: `WBP_TagSwitcher_C`

- Path: `/Game/Blueprints/WBP/Utility/WBP_TagSwitcher.WBP_TagSwitcher_C`, the class of the tab bar's buttons. Created with `Create`, with `Title`, `Txt_Title` and `Txt_Title_Highlight` emptied and its root `SizeBox` fixed with `SetMinDesiredWidth` and `SetMaxDesiredWidth`, it is a blank game-styled button with the tab hover. The API uses it for the two arrows of the paged tab bar (game 1.1.5024, probe 2026-10-22) and, since 0.1.3, for `row:mark`.
- A click calls `OnMouseButtonDown`; a post hook receives the widget as the context. It fires for every tab button in the game, so the handler must ignore widgets it did not create.
- The arrow picture is the game's texture `/Game/Arts/UI/Interaction/T_UI_RightArrow.T_UI_RightArrow`, put on top in an `Image` with `SetBrushFromTexture` (loaded after loading a save; `LoadAsset` also returns it).
- The arrows are put under the page box frame by re-adding the page box last in `Overlay_1` (`RemoveChild` then `AddChildToOverlay`): verified in game (2026-10-22, game 1.1.5024).
- The API collapses and shows the arrows with `SetVisibility`. That call was verified on the tab buttons, not on the arrows themselves: not verified in game yet.

### The tab widget as a small click target: `row:mark`

Verified in a probe (game 1.1.5024, UE4SS experimental, 2026-10-23, five rounds, API 0.1.2) while looking for a star button inside the rows of a scrolling list. Only the last candidate worked:

- `WBP_ButtonBase_C` (the game's button) in a `ScaleBox` at 0.7 inside a hand-made `ScrollBox` row: clicks reach `CommonButtonBase:HandleButtonClicked`, also after scrolling and after `ClearChildren` and a rebuild, and `SetButtonText` with ★ and ☆ works. But the button keeps a minimum width (about 175 on a 2000 px screenshot): `SetMinDimensions(0, 0)` changes nothing, and a `SizeBox` width override only narrows the slot while the button still draws at full width over its neighbours. Three Advanced recipes and three buttons do not fit.
- `WBP_RecipeItemTile_C` with the item `None`: it shows the tile's default item icon (Wooden Pulley) under the label, and after a click the item card stays on the mouse. With `SetRenderOpacity(0)` only the label shows, but hovering brings up the Wooden Pulley item card, and `SetToolTip(nil)` (no error) does not remove it: that card is not a UMG tooltip. Not usable.
- **`WBP_TagSwitcher_C`, what the API uses:** titles emptied, root `SizeBox` min and max desired width 40, `SetRenderOpacity(0)`, with a `TextBlock` on top (not hit-testable) in an `Overlay`, all in a `ScaleBox` at 0.6, slot aligned top in the probe (the API centers it vertically, as the player preferred in game on 2026-10-24). Only the label shows: no hover card or glow. Three Advanced recipes plus their marks fit in the two-thirds pane. Clicks reach the post hook on `OnMouseButtonDown` and toggled the label. Clicks were tested in the first column only.
- ★ (U+2605) and ☆ (U+2606) draw in the game's text font, in a `TextBlock` and as a button label.

### `WBP_IconButton_C`

- Path: `/Game/Blueprints/WBP/BuildOptionsPanel/WBP_IconButton.WBP_IconButton_C`. A round button with an icon and a short label (`Txt_Name`, a `CommonTextBlock`).
- A click calls `BndEvt__WBP_IconButton_Btn_Icon_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature`; a post hook on it receives the button as the context.
- Its icon was not set in the test (it showed the game's default).

## Smaller widgets: `ScaleBox`

Verified in game with a throwaway probe (layout probe 2, 2026-10-22, game 1.1.5024). All widgets were created with `StaticConstructObject` and outer `panel.WidgetTree`; buttons with `Create`.

- A `ScaleBox` (`/Script/UMG.ScaleBox`) with `SetStretch(7)` (UserSpecified) and `SetUserSpecifiedScale(0.7)` around a `TextBlock` shows the text at 0.7 and keeps its real layout size. Unlike `SetRenderScale`, which keeps the layout size of the unscaled widget, the box takes the room of the scaled child. Added to a page's `VerticalBox` it was centered horizontally (the slot default), so the page text is left-aligned with `SetHorizontalAlignment(1)` on its slot. That call was not in the probe; it is verified through the API (2026-10-22, game 1.1.5024, API 0.1.5): the small text starts at the left edge. The API versions named here are development builds from before the first public release (see [Versions](api.md#versions)).
- A `ScaleBox` at 0.6 around a `WBP_ButtonBase_C` gives a smaller button in the game's style (the API used 0.6 until 0.1.1; 0.1.2 uses 0.7, see "Look probe" below). Clicks arrive through `HandleButtonClicked` with the button's address, as usual.
- Arrow button: `ScaleBox` 0.6 > `Overlay` [ `WBP_ButtonBase_C` with an empty text, `Image` with `T_UI_RightArrow` (`SetBrushFromTexture`, `SetDesiredSizeOverride`, gold `SetColorAndOpacity`, `HitTestInvisible`) centered in the overlay slot ]. Clicks arrive. An image of 40 looked tiny inside the scaled button, so the API uses 64 (before scaling): verified in game through the API (2026-10-22, game 1.1.5024, API 0.1.5), the arrow looks right.
- Rejected: a `SizeBox` of 64 x 64 around the button squashes the button's art.
- `HorizontalBoxSlot:SetVerticalAlignment(2)` (center) on every child of a row puts a text next to a button or an item tile at mid height.

## Columns and spacers (API 0.1.1, verified in the V menu)

Verified in game on 2026-10-23 (game 1.1.5024, V menu, throwaway probe with the API 0.1.1 branch build):

- `page:columns(widths)`: a `HorizontalBox` added to the page's `VerticalBox` with a Fill slot, and a `VerticalBox` per pane added with `AddChildToHorizontalBox`. Each pane's slot gets `SetSize({ Value = weight, SizeRule = Fill(1) })`, and every pane after the first `SetPadding({ Left = 24 })` for the gap. All numbers are sent as floats.
- `pane:clear()`: `VerticalBox:ClearChildren()` on the pane's box.
- Spaces: `/Script/UMG.Spacer` with `SetSize({ X, Y })`, added to a `VerticalBox` (`page:space`) or a `HorizontalBox` (`row:space`).
- Results: two panes at a third and two thirds with the 24 gap; 4 tiles per row in the narrow grid; both scroll boxes scroll independently; clicks route in both panes, after `pane:clear()` and after `tab:refresh()`; clearing the right pane from left-pane tiles gave no flicker and left the left grid's scroll alone; small text is left-aligned; page and row spaces show.
- Content wider than its pane is cut silently (the scroll box clips). In the two-thirds pane a list row of three groups of 3 tiles joined by " + " with `row:space(32)` between groups was wider than the pane and lost its third group. One group of 3 tiles with 2 " + " texts takes about a third of that pane, and a 32 gap does not visually separate groups of tiles.
- Clearing a pane from a click on a button inside that same pane, with an input in the pane, was verified later through the API 0.1.2 and Cauldron Recipes (2026-10-23, game 1.1.5024): no flicker, the input keeps filtering.
- Not verified: columns and spaces in the TAB menu.

## Seen in the test

- A long `TextBlock` line does not wrap: it runs past the panel's edge. `SetAutoWrapText(true)` makes it wrap at the panel's edge (probe and API 0.1.3 template, 2026-10-21, both on a shown text and set at build time).
- `TextBlock:SetColorAndOpacity({ SpecifiedColor = { R, G, B, A }, ColorUseRule = 0 })` changes the text color (gold and grey, on a shown text and set at build time; probe and API 0.1.3 template, 2026-10-21). A light grey (0.7) on the panel's brown reads, but is hard to tell from white.
- **Never call `TextBlock:SetFont` with a Lua table: it crashes the game** (access violation). The API does not offer font changes. The default text font is size 24, typeface "Bold".
- A widget set to `Collapsed` measures 0 in `GetDesiredSize` and takes no room. After a change, `ForceLayoutPrepass()` on a parent updates the sizes in the same call (game 1.1.5024, probe 2026-10-22).
- `SetRenderScale` shrinks the drawing but keeps the layout size, so it does not make room. `SetShadowColorAndOpacity` with `SetShadowOffset` works, but the game's panel texts have no shadow. Neither is used.

## Look probe: dividers, scrollbar, search box, buttons (API 0.1.2)

Verified in game with a throwaway mod on a tab in the V menu (game 1.1.5024, UE4SS experimental, three rounds on 2026-10-23, API 0.1.1 build). The game data came from the FModel export (1.0.4963) and was re-checked by the probe. Widgets were made with `StaticConstructObject` and outer `panel.WidgetTree`, the game's own with `WidgetBlueprintLibrary:Create`.

### Horizontal divider: `WBP_EntryDivider_C`

- Path: `/Game/Blueprints/WBP/CatalogPanel/WBP_EntryDivider.WBP_EntryDivider_C`, the divider the V menu uses between categories. `Create` works and the class is loaded (no crash).
- Plain it measures 1020 x 16 (two halves with diamond ends); with a heading 1133 x 44.
- Heading: round 1 set `divider.Txt_BuildOptionType:SetText(...)` and the divider showed "Logistics", the blueprint's default `ShowText`, written back on `PreConstruct`. **Failed.** Round 2: `divider.ShowText = FText("Cauldron")` and `divider.Txt_BuildOptionType:SetText(FText("Cauldron"))` together, before adding the divider, work (the API sets both; whether `ShowText` alone is enough was not tried). The text is the game's dark color.
- No heading: `divider.Txt_BuildOptionType:SetVisibility(1)` (Collapsed) gives a plain line.

### Solid lines: `Image` + `SizeBox`

- An `Image` with no texture draws white. `SetColorAndOpacity` tints it, `SetVisibility(3)` makes it ignore the mouse.
- **Failed:** `Image:SetDesiredSizeOverride` is ignored: lines came out about 40 thick, horizontal and vertical.
- Works: the `Image` inside a `SizeBox` (`/Script/UMG.SizeBox`) with `SetHeightOverride(2.0)` (horizontal) or `SetWidthOverride(2.0)` (vertical). A vertical one in a `HorizontalBox` slot with `SetVerticalAlignment(0)` (Fill) spans the row, with a `Spacer` of 16 on each side. A horizontal one in a `VerticalBox` slot with `SetHorizontalAlignment(0)` fills the width.
- Color: the divider art is sRGB #7A6C5F. As a linear value (0.195, 0.152, 0.114) it read as a faint dark band; used as is (0.478, 0.424, 0.373) it is a light line, which is the one picked.
- Three Advanced recipes per row (3 groups with lines) fit in the two-thirds pane: 832 x 100; two Normal ones 803 x 100.

### Scrollbar

- The live item sheet is destroyed when the V menu closes, but the class's widget-tree templates were still found afterwards (the class was loaded in that session; if the owning class is not loaded yet, for example before the V menu was ever opened, the API loads it first with `LoadAsset`, which is not verified): `StaticFindObject("/Game/Blueprints/WBP/CatalogPanel/WBP_CatalogContent.WBP_CatalogContent_C:WidgetTree.ScrollBox_40")` finds one.
- Works: `list.WidgetBarStyle = template.WidgetBarStyle` and `list.ScrollbarThickness = template.ScrollbarThickness` on a new `ScrollBox` **before** adding it: the game's scrollbar (frame and thumb, thickness 22), no crash.
- Partial: the same copy after `AddChild` applied only partly (a thin track, no frame). So the API copies before adding.
- `FindFirstOf("WBP_CatalogContent_C")` gave nothing usable (the live widget is gone while the menu is closed), hence the template.

### Search box

- `StaticFindObject("/Game/Blueprints/WBP/BuildOptionsPanel/WBP_BuildPanelNew.WBP_BuildPanelNew_C:WidgetTree.Edit_BlueprintSearch")` finds a template (`FindFirstOf("WBP_BuildPanelNew_C")` found no live panel).
- Works: `box.WidgetStyle = template.WidgetStyle` on a new `EditableTextBox` before adding it, then `SetHintText`: the game's brown rounded box with a dark hint, no crash. Typing, `GetText` and the polling with this style were not tried.
- Both copies (scrollbar and search) ran in one session without a crash. Structs are only ever copied from a game widget, never built from a Lua table.

### Buttons and page padding

- `ScaleBox` + `WBP_ButtonBase_C`, text "+ Add": desired sizes 120 x 30 at 0.6, 140 x 35 at 0.7, 160 x 40 at 0.8, 200 x 50 at 1.0 with padding 8. `button.ContentBorder:SetPadding({ Left = 10, Top = 0, Right = 10, Bottom = 0 })` did not change `GetDesiredSize` (probably a minimum width in the button style) but looked narrower on screen. Picked by eye: 0.7 with padding 10 (the API later raised it to 16, see below).
- V menu page padding: read as left 24, top 20, right 24, bottom 16. With top 20 the first line sat under the frame's top-left ornament. Picked by eye: left 40, top 36.

### Text color (not changed by the API)

Every item sheet text (`Txt_UsedInTitle`, `Txt_ItemName`, `Txt_ItemDesc`, `Txt_ItemType`, `Txt_ApproachesTitle`) and the default CommonUI text styles read `ColorAndOpacity` R 0.022, G 0.033, B 0.053 (linear, sRGB #293341), `ColorUseRule` 0. The game's panels draw dark text; white, gold or cream texts of a mod clash with them. The API leaves text colors to the mod (`text:color`).

### Through the API 0.1.2 (in-game test)

Verified in game with a test mod (`api-look-test`) and Cauldron Recipes 0.1.1 on the API 0.1.2 test build (2026-10-23, game 1.1.5024, UE4SS experimental). The log had no "could not" or "not found" line.

- Page padding 40 / 36 / 24 / 16 clears the corner ornament.
- `page:columns({ 1, 2 }, { divider = true })`: the line shows between the panes.
- `pane:divider()` plain (narrow pane) and with a heading; `row:divider()` in list rows and pane rows; three Advanced groups per row fit in the two-thirds pane with the padding of 40.
- `section:divider("Cauldron")` on the Goods item sheet fits.
- The game's scrollbar on a list and a grid, also in the Recipes tab (the TAB menu was opened before the V menu).
- The game's search box: hint, `set("abc")` then `get()` returns "abc", `onChange` fires on each typed change, `set("")` from a button.
- Small buttons click. "Show advanced" filled its button at padding 10, so the API uses 16; 16 looked right.

Still not verified: the `LoadAsset` fallback when a style or widget class is not loaded; `ShowText` alone (without `SetText` on the inner text) for a heading; the column divider and the scrollbar in the TAB menu.
