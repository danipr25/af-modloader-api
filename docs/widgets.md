# Game widgets for pages

Widgets a page can use besides plain UMG text and boxes, and how a click reaches Lua. Game 1.1.5023, UE4SS 1181, verified in game on 2026-10-21 with a throwaway mod on a tab added by the API. Signatures come from the FModel export and the UE4SS header dump.

## A grid of item tiles

A `WrapBox` (`/Script/UMG.WrapBox`, created with `StaticConstructObject` and outer `panel.WidgetTree`) inside a `ScrollBox` whose slot fills the page lays tiles out in rows, like the Recognition page, and scrolls. `AddChildToWrapBox(tile)` adds a tile. In the TAB menu it gave 4 tiles per row.

## Item tile that can be clicked: `WBP_RecipeItemTile_C`

- Path: `/Game/Blueprints/WBP/Utility/WBP_RecipeItemTile.WBP_RecipeItemTile_C`. Parent class `BeltTDUserWidget`. Created with `WidgetBlueprintLibrary:Create(panel, class, playerController)`.
- `UpdateItemInfo(FName ConfigName, int32 ItemCount, double ProducePr, double ProduceSpeed, bool ForceRefresh, bool ShowPrDown, bool IconSmall)`: called as `(FName(item), count, 0.0, 0.0, true, false, false)` it shows the item icon, and hovering shows the game's item card (name and buying price).
- Clicking it calls its `OnMouseButtonDown`. A post hook on `WBP_RecipeItemTile_C:OnMouseButtonDown` receives the tile as the context, so the clicked tile is known by comparing addresses. With its `ClickEvent` property left at `false` (the default), the game does nothing else on the click.
- The hook fires for every `WBP_RecipeItemTile_C` in the game, so the handler must ignore tiles it did not create.

`WBP_SimpleItemTile_C` (used by the API's `row:item`) has no click function.

## Buttons

### `WBP_ButtonBase_C`

- Path: `/Game/Blueprints/WBP/Utility/WBP_ButtonBase.WBP_ButtonBase_C`. Parent chain `LyraButtonBase` (game) then `CommonButtonBase` (CommonUI). Created with `Create`. The game's teal button with a text label.
- `SetButtonText(FText)` (from `LyraButtonBase`) sets the label.
- A click calls `/Script/CommonUI.CommonButtonBase:HandleButtonPressed` and then `HandleButtonClicked`; post hooks on both receive the button as the context. `BP_OnClicked` never fired.
- These hooks fire for every CommonUI button in the game: the handler must ignore buttons it did not create.

### `WBP_IconButton_C`

- Path: `/Game/Blueprints/WBP/BuildOptionsPanel/WBP_IconButton.WBP_IconButton_C`. A round button with an icon and a short label (`Txt_Name`, a `CommonTextBlock`).
- A click calls `BndEvt__WBP_IconButton_Btn_Icon_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature`; a post hook on it receives the button as the context.
- Its icon was not set in the test (it showed the game's default).

## Seen in the test

- A long `TextBlock` line does not wrap: it runs past the panel's edge. Wrapping (`SetAutoWrapText`) was not tested.
