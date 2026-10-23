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

- Path: `/Game/Blueprints/WBP/Utility/WBP_TagSwitcher.WBP_TagSwitcher_C`, the class of the tab bar's buttons. Created with `Create`, with `Title`, `Txt_Title` and `Txt_Title_Highlight` emptied and its root `SizeBox` fixed with `SetMinDesiredWidth` and `SetMaxDesiredWidth`, it is a blank game-styled button with the tab hover. The API uses it for the two arrows of the paged tab bar (game 1.1.5024, probe 2026-10-22).
- A click calls `OnMouseButtonDown`; a post hook receives the widget as the context. It fires for every tab button in the game, so the handler must ignore widgets it did not create.
- The arrow picture is the game's texture `/Game/Arts/UI/Interaction/T_UI_RightArrow.T_UI_RightArrow`, put on top in an `Image` with `SetBrushFromTexture` (loaded after loading a save; `LoadAsset` also returns it).
- The arrows are put under the page box frame by re-adding the page box last in `Overlay_1` (`RemoveChild` then `AddChildToOverlay`): verified in game (2026-10-22, game 1.1.5024).
- The API collapses and shows the arrows with `SetVisibility`. That call was verified on the tab buttons, not on the arrows themselves: not verified in game yet.

### `WBP_IconButton_C`

- Path: `/Game/Blueprints/WBP/BuildOptionsPanel/WBP_IconButton.WBP_IconButton_C`. A round button with an icon and a short label (`Txt_Name`, a `CommonTextBlock`).
- A click calls `BndEvt__WBP_IconButton_Btn_Icon_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature`; a post hook on it receives the button as the context.
- Its icon was not set in the test (it showed the game's default).

## Smaller widgets: `ScaleBox`

Verified in game with a throwaway probe (layout probe 2, 2026-10-22, game 1.1.5024). All widgets were created with `StaticConstructObject` and outer `panel.WidgetTree`; buttons with `Create`.

- A `ScaleBox` (`/Script/UMG.ScaleBox`) with `SetStretch(7)` (UserSpecified) and `SetUserSpecifiedScale(0.7)` around a `TextBlock` shows the text at 0.7 and keeps its real layout size. Unlike `SetRenderScale`, which keeps the layout size of the unscaled widget, the box takes the room of the scaled child. Added to a page's `VerticalBox` it was centered horizontally (the slot default), so the page text is left-aligned with `SetHorizontalAlignment(1)` on its slot. That call was not in the probe; it is verified through the API (2026-10-22, game 1.1.5024, API 0.1.5): the small text starts at the left edge. The API versions named here are development builds from before the first public release (see [Versions](api.md#versions)).
- A `ScaleBox` at 0.6 around a `WBP_ButtonBase_C` gives a smaller button in the game's style. Clicks arrive through `HandleButtonClicked` with the button's address, as usual.
- Arrow button: `ScaleBox` 0.6 > `Overlay` [ `WBP_ButtonBase_C` with an empty text, `Image` with `T_UI_RightArrow` (`SetBrushFromTexture`, `SetDesiredSizeOverride`, gold `SetColorAndOpacity`, `HitTestInvisible`) centered in the overlay slot ]. Clicks arrive. An image of 40 looked tiny inside the scaled button, so the API uses 64 (before scaling): verified in game through the API (2026-10-22, game 1.1.5024, API 0.1.5), the arrow looks right.
- Rejected: a `SizeBox` of 64 x 64 around the button squashes the button's art.
- `HorizontalBoxSlot:SetVerticalAlignment(2)` (center) on every child of a row puts a text next to a button or an item tile at mid height.

## Columns and spacers (API 0.1.1, not verified in game)

Written from the Unreal Engine documentation, to be filled with the in-game result:

- `page:columns(widths)`: a `HorizontalBox` added to the page's `VerticalBox` with a Fill slot, and a `VerticalBox` per pane added with `AddChildToHorizontalBox`. Each pane's slot gets `SetSize({ Value = weight, SizeRule = Fill(1) })`, and every pane after the first `SetPadding({ Left = 24 })` for the gap. All numbers are sent as floats.
- `pane:clear()`: `VerticalBox:ClearChildren()` on the pane's box.
- Spaces: `/Script/UMG.Spacer` with `SetSize({ X, Y })`, added to a `VerticalBox` (`page:space`) or a `HorizontalBox` (`row:space`).
- To check in game: the page's width in the V menu, tiles per row in a narrow pane, whether a long list row is cut at the pane's edge, two scroll boxes side by side, and clearing a pane inside the click of one of its tiles.

## Seen in the test

- A long `TextBlock` line does not wrap: it runs past the panel's edge. `SetAutoWrapText(true)` makes it wrap at the panel's edge (probe and API 0.1.3 template, 2026-10-21, both on a shown text and set at build time).
- `TextBlock:SetColorAndOpacity({ SpecifiedColor = { R, G, B, A }, ColorUseRule = 0 })` changes the text color (gold and grey, on a shown text and set at build time; probe and API 0.1.3 template, 2026-10-21). A light grey (0.7) on the panel's brown reads, but is hard to tell from white.
- **Never call `TextBlock:SetFont` with a Lua table: it crashes the game** (access violation). The API does not offer font changes. The default text font is size 24, typeface "Bold".
- A widget set to `Collapsed` measures 0 in `GetDesiredSize` and takes no room. After a change, `ForceLayoutPrepass()` on a parent updates the sizes in the same call (game 1.1.5024, probe 2026-10-22).
- `SetRenderScale` shrinks the drawing but keeps the layout size, so it does not make room. `SetShadowColorAndOpacity` with `SetShadowOffset` works, but the game's panel texts have no shadow. Neither is used.
