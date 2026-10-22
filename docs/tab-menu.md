# The TAB menu

How the in-game TAB menu (tabs Player, World, Recognition) is built, so the API can add tabs to it. Game 1.1.5023 (1.1.5024 for the paging section), checked on 2026-10-20 by walking the live widget tree with a read-only UE4SS Lua script while the menu was open, plus the UE4SS C++ header dump.

## Where it lives

The game's UI uses CommonUI. The root layout is `WBP_RootUILayout_C` (an `Overlay` with several `CommonActivatableWidgetStack` layers). CommonUI stacks keep their screens in `WidgetList` and `DisplayedWidget` (class `CommonActivatableWidgetContainerBase`), not in panel slots, so a tree walk has to read those to go inside.

With the TAB menu open, the `GameMenu_Stack` layer (inside `SLB_GameMenu`, a `ScaleBox`) displays one screen: **`WBP_PlayerGearPanel_C`**. That is the TAB menu.

## Structure of `WBP_PlayerGearPanel_C`

```
WBP_PlayerGearPanel_C
└─ Overlay_1
   ├─ TagSwithcer            WBP_TagSwitcherGroup_C   the tab bar (name spelled this way in the game)
   │  └─ SizeBox_19
   │     └─ EntryPanel       HorizontalBox            one WBP_TagSwitcher_C per tab
   └─ SizeBox_41
      └─ Border_45
         └─ WidgetSwitcher_0 WidgetSwitcher            one page per tab, same order
            ├─ VerticalBox_1   Player: GearList, PlayerBuffList
            ├─ ScrollBox_1     World: GlobalBuffList
            └─ ScrollBox_0     Recognition: LicenseList (WrapBox of WBP_LicenseSimpleTile_C)
```

The tab bar's `TitleList` read in game: `Player | World | Recognition`.

## The tab bar: `WBP_TagSwitcherGroup_C`

A reusable widget; the game uses it in five panels. From the header dump (`WBP_TagSwitcherGroup.hpp`):

| Member | Type | Meaning |
|---|---|---|
| `EntryPanel` | `HorizontalBox` | Holds the tab buttons. |
| `TitleList` | `TArray<FText>` | Tab titles, in order. |
| `EntryList` | `TArray<WBP_TagSwitcher_C*>` | The tab buttons, in order. |
| `OnTagSwitch` | delegate | Fired when the active tab changes. |
| `SetActive(int32 ActiveIndex)` | function | Selects a tab. |
| `OnEntryClick(int32)` | function | Click handler of a tab button. |

Each tab button, `WBP_TagSwitcher_C` (`WBP_TagSwitcher.hpp`), has `Txt_Title`, `Border_Highlight`, `Title` (FText), `Index` (int32), `IsActive`, and `SetActive(bool)`.

`WBP_PlayerGearPanel_C` reacts to `OnTagSwitch` through its own bound event and switches `WidgetSwitcher_0`. Whether it uses the index directly has not been verified.

Other tab bars found in game (titles read live): catalog `Materials | Goods | Stats | Ledger`, workbench `Unlocks | Equipment`, build panel `Build | Blueprints`, mailbox `Quests | Loans`.

## Adding a tab (verified in game 2026-10-20)

Tested on game 1.1.5023 with UE4SS 1181 and a throwaway Lua mod loaded by AF Mod Loader.

- The TAB menu panel is created once and **reused**: every time the menu opens, the same `WBP_PlayerGearPanel_C` instance gets `BP_OnActivated` (and `BP_OnDeactivated` when it closes).
- In game 1.1.5023 the tab bar was seen rebuilding its buttons when the menu opened after titles were added; that may have been the API's own rebuild (it calls `PreConstruct` itself when it adds titles). In game 1.1.5024, opening TAB again without changes does not recreate the buttons: tab buttons hidden with `SetVisibility` stay hidden after closing and opening TAB.
- Package paths: `/Game/Blueprints/WBP/PlayerGear/WBP_PlayerGearPanel.WBP_PlayerGearPanel_C` and `/Game/Blueprints/WBP/Utility/WBP_TagSwitcherGroup.WBP_TagSwitcherGroup_C`. In the spike, post hooks on their functions registered at once. With the API (2026-10-21) three of its hooks were not available when it started and registered on a later retry, so the API keeps retrying instead of relying on this.
- Hookable (post hooks, as for every Blueprint function): `BP_OnActivated`, `BP_OnDeactivated`, the group's `PreConstruct` and `OnEntryClick(int32)`, and the panel's `BndEvt__WBP_PlayerGearPanel_TagSwithcer_K2Node_ComponentBoundEvent_0_OnTagSwitch__DelegateSignature(int32)`. A click on a tab calls the panel's `OnTagSwitch` handler, then the group's `OnEntryClick`, with the tab index.
- **What works:** with the menu open, append a title to `TitleList` (`list[#list + 1] = FText("...")`), call `EntryPanel:ClearChildren()` and `EntryList:Empty()`, then `PreConstruct(false)` on the group. The game builds the fourth button itself, wired to its click handling. Then add the page with `WidgetSwitcher_0:AddChild(widget)`: the panel's own handler switches `WidgetSwitcher_0` to index 3 when the tab is clicked. The tab and page stay when the menu is closed and opened again (same instance, and `TitleList` keeps the extra title).
- **What does not work:** creating a `WBP_TagSwitcher_C` by hand and adding it to `EntryPanel` and `EntryList`. The button shows but clicking it does nothing.
- Page widgets: plain UMG widgets (`VerticalBox`, `TextBlock`, `EditableTextBox`) created with `StaticConstructObject(class, panel.WidgetTree)`, and game user widgets created with `WidgetBlueprintLibrary:Create(panel, class, playerController)`, display correctly. Text typed in an `EditableTextBox` on the page reaches the box (the game does not take the keys as shortcuts).
- `WBP_SimpleItemTile_C` (`/Game/Blueprints/WBP/...`, created with `Create`) shows an item icon after `UpdateItemInfo(FName(item), 1, 0, false)`, and its hover tooltip is the game's full item card (localized name, category, where it is crafted).

Verified with the API on 2026-10-21: two added tabs work; loading another save gives a new panel instance that gets the tabs once; after a UE4SS mods restart the titles and pages stay in the live panel (the Lua state is gone, the widgets are not). The tab bar has a fixed width: with five tabs the last button is pushed out of line (see the next section).

Not tested yet: gamepad navigation to the new tab. Keyboard: no keys switch tabs (Q/E and A/D are used by the game for other things).

## Paging the tab bar (API 0.1.4)

Verified in game 1.1.5024 on 2026-10-22 with two throwaway probes (tab bar and arrows; widths, texture and page box). The API's use of them is verified in game with API 0.1.4 build 5ffee40 (2026-10-22, see below).

- The bar (`TagSwithcer`) is child 0 of `Overlay_1` (an `Overlay`), slot padding L16 T0 R0 B0, render translation (0, -68). Child 1 is the page box `SizeBox_41` (`WidthOverride` 580, `bOverride_WidthOverride` on), found by class (the one `SizeBox` child of `group:GetParent()`; it was child 1 before the API added anything). The API reads that width, minus the bar's left padding, as the room for the bar.
- Tab widths, measured with the menu open (`GetDesiredSize().X`): Player 128, World 128, Recognition 154, Cauldron Recipes 199, a tab titled "Bar" 128. A tab is never narrower than 128. `EntryPanel` is as wide as the sum of its tabs (737 = 128 + 128 + 154 + 199 + 128): no padding between tabs. With the menu closed every size reads 0.
- At `BP_OnActivated`, every size reads 0 until `group:ForceLayoutPrepass()` runs; after it, every visible tab's width is right in the same call. Collapsing or showing a tab and calling it again updates the widths at once. A collapsed tab measures 0, so only visible tabs can be measured.
- `SetVisibility(Collapsed)` (1) on a tab button (an `EntryList` entry) hides it and the others close up; `Visible` (0) shows it again. `TitleList` and the tab indexes do not change, so every visible tab still opens its own page. Hidden tabs stay hidden after closing and opening TAB.
- The bar's slot padding can be changed with `group.Slot:SetPadding({ Left, Top, Right, Bottom })` to leave room for arrows.
- An arrow is the game's own tab widget (`WBP_TagSwitcher_C`, created with `WidgetBlueprintLibrary:Create`) with an empty title (`Title`, `Txt_Title`, `Txt_Title_Highlight`) and its root `SizeBox` narrowed with `SetMinDesiredWidth` and `SetMaxDesiredWidth` (64 gave 64 x 100). It looks like a tab and has the tab hover. The game's texture `/Game/Arts/UI/Interaction/T_UI_RightArrow.T_UI_RightArrow` goes on top in an `Image` (`SetBrushFromTexture`, `SetDesiredSizeOverride` 36, gold `SetColorAndOpacity`, `HitTestInvisible`, mirrored with `SetRenderScale(-1, 1)` for "previous"). Both sit in a small `Overlay` added to `Overlay_1` (left: horizontal Left with padding L16; right: horizontal Right; both vertical Top, render translation (0, -68)). Widgets added to `Overlay_1` stay there across menu opens.
- The texture is already loaded right after loading a save, with no machine panel opened; `LoadAsset` of it also returns it without problems.
- A click on an arrow fires a post hook on `WBP_TagSwitcher_C:OnMouseButtonDown` (path `/Game/Blueprints/WBP/Utility/WBP_TagSwitcher.WBP_TagSwitcher_C`) once, with the arrow as the context (any mouse button; it also fires for the real tabs, told apart by address). A clicked arrow does not stay active or highlighted.
- `group:SetActive(1)` does not fire the panel's `OnTagSwitch`. A mouse click on a tab fires `OnTagSwitch` and then `OnEntryClick`, with a 0-based index.

The arrows would be drawn over the page box's frame (they come after it in `Overlay_1`, and later children draw on top), while the real tabs are under it. So the API puts the arrows under the frame by taking the page box out and adding it last (`overlay:RemoveChild(box)`, `overlay:AddChildToOverlay(box)`, then the same padding and alignments on the new slot). Verified in game (2026-10-22, game 1.1.5024): the arrows sit under the frame like the tabs, the page box keeps its size and place, and the pages work. If it fails the arrows stay over the frame and the log says so.

What the API does with it: paging is on only when the tabs' widths add up to more than the room. Then it shows the longest run of whole tabs that fits in the room minus two arrows (64 wide plus a 4 gap each), collapses the others, pads the bar for the arrows, and each click moves by one view (next brings at least the next tab into view and fills the view; previous brings at least the previous tab into view and fills the view). It measures at `BP_OnActivated` after adding the tabs, and applies again after each arrow click. If the menu cannot be read or the tabs could not be added, every tab is shown again, the padding restored and the arrows hidden. The first time a Lua state sees a panel it also removes arrows left by an earlier Lua state (the widgets survive a mods restart, the Lua state does not), takes their padding off and shows every tab; after a mods restart every tab showed again (user, 2026-10-22, on the build before the page box was moved over the arrows).

