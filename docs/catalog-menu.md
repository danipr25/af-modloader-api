# The V menu (item catalog)

How the in-game V menu (tabs Materials, Goods, Stats, Ledger) is built, so the API can add tabs to it and sections to its item sheet (API 0.1.7). Game 1.1.5024. Facts marked **verified** were observed in game on 2026-10-22 with a throwaway probe mod (hooks, widget names, adding a tab, a page and an item sheet section). Everything else is **unverified**: it is written from that probe and from the TAB menu work, and waits for the in-game test of the API.

## Structure

The V menu is `WBP_CatalogPanel_C` (`/Game/Blueprints/WBP/CatalogPanel/WBP_CatalogPanel.WBP_CatalogPanel_C`; the HUD calls it `ProductCatalogWidget`, in the `GameMenu` layer). **Verified** members:

| Member | Meaning |
|---|---|
| `WBP_TagSwitcherGroup` | The tab bar: the same `WBP_TagSwitcherGroup_C` class as the TAB menu's (`TitleList`, `EntryList`, `EntryPanel`, `OnEntryClick`, `SetActive`). Titles `Materials \| Goods \| Stats \| Ledger`. |
| `SW_Main` | A `WidgetSwitcher`: the pages. Child 0 is `Ovl_Main` (the item sheet and its lists), child 1 `WBP_ProductionDetails` (Stats), child 2 `WBP_LedgerContent` (Ledger). |
| `PageSwitcher` | A second `WidgetSwitcher`, used inside `Ovl_Main` (0 for Materials, 1 for Goods). |
| `Ovl_Main`, `CatalogContent` | The item sheet area. |
| `CurrentActivePage` | The index of the active page. |

The tab titles and the pages do **not** match one to one: Materials and Goods share the page `Ovl_Main`. So the menu has four titles and three pages, and the page of title position `p` (1-based) is `SW_Main` child `p - 2` for `p >= 3`. The game itself sets `SW_Main` to `tab - 1` for tabs 2 and up (**verified**: the fifth tab showed `SW_Main` child 3 before the probe did anything). The API handles this with a page offset of 1 in its tab plan (`tabs_plan.lua`): `pages == titles - 1`, and the page of the title at position `p` is child `p - 1 - 1`.

Hooks that fire (**verified**): `BP_OnActivated` on every open, the bound event `BndEvt__WBP_CatalogPanel_WBP_TagSwitcherGroup_K2Node_ComponentBoundEvent_0_OnTagSwitch__DelegateSignature(index)` on every tab click, and `SetActivePage`. The panel object is reused: reopening the menu gives `BP_OnActivated` again on the same instance.

## Adding a tab (verified in the probe)

The same mechanism as the TAB menu ([tab-menu.md](tab-menu.md)), done after `BP_OnActivated`:

1. Create a `VerticalBox` with `StaticConstructObject` (outer: the panel's `WidgetTree`), add it to `SW_Main` with `AddChild`.
2. Append the title to `TitleList`, call `EntryPanel:ClearChildren()`, `EntryList:Empty()`, then `PreConstruct(false)` on the group.

Result in the probe: the fifth tab showed, clicking it showed the page, the other tabs kept working, and reopening the menu kept one tab. A page's text sat on the panel's top-left frame corner, so the API pads its pages (`SetPadding` on the slot returned by `AddChild`; **unverified**, the values are a first guess: left 24, top 20, right 24, bottom 16). The API logs once if the call fails.

More than one tab in this menu is **unverified**. The API adds one page per tab in order, which is the page the game's `tab - 1` rule shows, but only one extra tab was tested.

The highlighted tab after the bar is rebuilt is restored with `SetActive(panel.CurrentActivePage)`. The probe used `CurrentActivePage` this way. Whether it is always the index of the highlighted tab (for example while Goods, Stats or Ledger is showing) is **not fully verified**.

No paging: the V bar is wider than the TAB bar. With five tabs it fits. More tabs than fit are not handled in this version.

### The panel class may not be loaded at start

`WBP_CatalogPanel_C` was not loaded when the API starts. The API registers the V menu hooks (`BP_OnActivated`, `BP_OnDeactivated`) when the class appears: the `PreConstruct` hook of the tab bar group (already used for the TAB menu) fires for the V menu's group too, and when the V menu panel is found it only schedules the registration with `ExecuteInGameThread`. Nothing touches a tab bar from inside `PreConstruct`, because that crashed the game in the TAB menu (see [tab-menu.md](tab-menu.md)). In that deferred call the API checks whether the menu is already open (`IsActivated`, **unverified**) and adds the tabs at once if so. If that timing fails, the tabs appear the next time the menu opens. After the registration, `BP_OnActivated` does the work on every open. This sequence is **unverified**.

## Selecting a tab

`WBP_TagSwitcherGroup:OnEntryClick(index)` selects a tab as if it was clicked (**verified** in the probe, called from a button click through `ExecuteInGameThread`: calling it inside the click hook directly is not what was tested). `tab:select()` computes the index from the live `TitleList` and defers the call the same way.

## The item sheet

The item sheet is `WBP_CatalogContent_C` (`/Game/Blueprints/WBP/CatalogPanel/WBP_CatalogContent.WBP_CatalogContent_C`). Materials and Goods have **different instances**. **Verified**:

- `UpdateContent` (a post hook) fires for every item shown, and `ConfigName.ConfigName` then holds the item's row name.
- `Vtb_UsedIn` is the "Used in Crafting" list, and its parent is a `VerticalBox`. A `VerticalBox` of a text and a `HorizontalBox` with a `WBP_ButtonBase_C` appended to that parent shows under "Used in Crafting" and above the records. Clicks on the button arrive through `HandleButtonClicked`, as everywhere else.

The API's sections (`api.catalog.section`) use this: after every `UpdateContent`, each mod's section on that sheet is rebuilt. One `VerticalBox` per mod per sheet is kept under `Vtb_UsedIn:GetParent()`; before each rebuild it is checked (still valid, still under that parent), cleared (`ClearChildren`) and filled again by the mod's `build`, with a new page session (so handles from the previous item go dead). **Unverified**: clearing and rebuilding inside the post hook (the probe built the section once and then only changed a text), and `GetParent()` on the box. The `UpdateContent` hook is registered when the V menu panel is first seen (the sheet class is loaded with it) and again on each open if needed. Items shown before that have no section: the first `UpdateContent` after the hook exists builds it.
