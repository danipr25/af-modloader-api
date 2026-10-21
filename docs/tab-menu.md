# The TAB menu

How the in-game TAB menu (tabs Player, World, Recognition) is built, so the API can add tabs to it. Game 1.1.5023, checked on 2026-10-20 by walking the live widget tree with a read-only UE4SS Lua script while the menu was open, plus the UE4SS C++ header dump.

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
- Each time the menu opens, the tab bar runs `PreConstruct` again and rebuilds its buttons from `TitleList`.
- Package paths: `/Game/Blueprints/WBP/PlayerGear/WBP_PlayerGearPanel.WBP_PlayerGearPanel_C` and `/Game/Blueprints/WBP/Utility/WBP_TagSwitcherGroup.WBP_TagSwitcherGroup_C`. In the spike, post hooks on their functions registered at once. With the API (2026-10-21) three of its hooks were not available when it started and registered on a later retry, so the API keeps retrying instead of relying on this.
- Hookable (post hooks, as for every Blueprint function): `BP_OnActivated`, `BP_OnDeactivated`, the group's `PreConstruct` and `OnEntryClick(int32)`, and the panel's `BndEvt__WBP_PlayerGearPanel_TagSwithcer_K2Node_ComponentBoundEvent_0_OnTagSwitch__DelegateSignature(int32)`. A click on a tab calls the panel's `OnTagSwitch` handler, then the group's `OnEntryClick`, with the tab index.
- **What works:** with the menu open, append a title to `TitleList` (`list[#list + 1] = FText("...")`), call `EntryPanel:ClearChildren()` and `EntryList:Empty()`, then `PreConstruct(false)` on the group. The game builds the fourth button itself, wired to its click handling. Then add the page with `WidgetSwitcher_0:AddChild(widget)`: the panel's own handler switches `WidgetSwitcher_0` to index 3 when the tab is clicked. The tab and page stay when the menu is closed and opened again (same instance, and `TitleList` keeps the extra title).
- **What does not work:** creating a `WBP_TagSwitcher_C` by hand and adding it to `EntryPanel` and `EntryList`. The button shows but clicking it does nothing.
- Page widgets: plain UMG widgets (`VerticalBox`, `TextBlock`, `EditableTextBox`) created with `StaticConstructObject(class, panel.WidgetTree)`, and game user widgets created with `WidgetBlueprintLibrary:Create(panel, class, playerController)`, display correctly. Text typed in an `EditableTextBox` on the page reaches the box (the game does not take the keys as shortcuts).
- `WBP_SimpleItemTile_C` (`/Game/Blueprints/WBP/...`, created with `Create`) shows an item icon after `UpdateItemInfo(FName(item), 1, 0, false)`, and its hover tooltip is the game's full item card (localized name, category, where it is crafted).

Verified with the API on 2026-10-21: two added tabs work; loading another save gives a new panel instance that gets the tabs once; after a UE4SS mods restart the titles and pages stay in the live panel (the Lua state is gone, the widgets are not). The tab bar has a fixed width: with five tabs the last button is pushed out of line.

Not tested yet: gamepad or keyboard navigation to the new tab.
