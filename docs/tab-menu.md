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

## Not verified yet

Adding a fourth tab means adding a `WBP_TagSwitcher_C` to `EntryPanel` and `EntryList`, a title to `TitleList`, and a page to `WidgetSwitcher_0`. Whether the panel's own switching logic accepts a fourth index, and whether the game rebuilds the bar (dropping added entries) when the menu reopens, still has to be tested in game.
