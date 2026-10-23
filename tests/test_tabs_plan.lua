-- Contract of the tab plan: what to add to a panel, given what the live panel looks like.
local lu = require("luaunit")
local plan = require("tabs_plan")

local BASE = { "Player", "World", "Recognition" }

local function titles(...)
  local list = { table.unpack(BASE) }
  for _, title in ipairs({ ... }) do
    list[#list + 1] = title
  end
  return list
end

local TABS = {
  { key = "a/one", title = "One" },
  { key = "a/two", title = "Two" },
}

local function state(overrides)
  local value = { titles = titles(), childCount = 3, tabs = TABS, pageIndex = {} }
  for key, item in pairs(overrides) do
    value[key] = item
  end
  return value
end

return {
  TestTabsPlan = {
    testFreshPanelGetsEveryTabInOrder = function()
      local result = plan.compute(state({}))
      lu.assertTrue(result.ok)
      lu.assertEquals(result.appendKeys, { "a/one", "a/two" })
    end,

    testCompletePanelNeedsNothing = function()
      local result = plan.compute(
        state({ titles = titles("One", "Two"), childCount = 5, pageIndex = { ["a/one"] = 3, ["a/two"] = 4 } })
      )
      lu.assertTrue(result.ok)
      lu.assertEquals(result.appendKeys, {})
    end,

    testOnlyTheMissingTabsAreAdded = function()
      local result = plan.compute(state({ titles = titles("One"), childCount = 4, pageIndex = { ["a/one"] = 3 } }))
      lu.assertTrue(result.ok)
      lu.assertEquals(result.appendKeys, { "a/two" })
    end,

    testTitlesLeftFromBeforeALuaRestartAreRefused = function()
      -- Our titles are in the menu, but this Lua state has no pages: nothing is injected.
      local result = plan.compute(state({ titles = titles("One", "Two"), childCount = 5, pageIndex = {} }))
      lu.assertFalse(result.ok)
      lu.assertStrContains(result.reason, "did not create")
    end,

    testTitleOfAnotherModBetweenOursIsRefused = function()
      local result =
        plan.compute(state({ titles = titles("One", "Other"), childCount = 5, pageIndex = { ["a/one"] = 3 } }))
      lu.assertFalse(result.ok)
      lu.assertStrContains(result.reason, "something else")
    end,

    testTitlesWithoutMatchingPagesAreRefused = function()
      local result = plan.compute(state({ titles = titles("Other"), childCount = 3 }))
      lu.assertFalse(result.ok)
      lu.assertStrContains(result.reason, "tab titles but")
    end,

    testPageWhoseTitleIsGoneIsRefused = function()
      local result = plan.compute(state({ childCount = 4, pageIndex = { ["a/one"] = 3 } }))
      lu.assertFalse(result.ok)
      lu.assertStrContains(result.reason, "title is gone")
    end,

    testCleanupSelectsOnlyTitlesThisStateAdded = function()
      -- Only tabs with a page made by this state are removed; the game's own titles are never listed.
      lu.assertEquals(plan.titlesToRemove(TABS, { ["a/one"] = true }), { "One" })
      lu.assertEquals(plan.titlesToRemove(TABS, {}), {})
    end,

    testCatalogOffsetOneMatchesTitlesToPages = function()
      -- The V menu: Materials, Goods, Stats, Ledger have 3 pages (Materials and Goods share one), so our first tab
      -- is title 5 and page index 3.
      local catalog = { "Materials", "Goods", "Stats", "Ledger" }
      local function catalogState(overrides)
        local value = { titles = catalog, childCount = 3, tabs = TABS, pageIndex = {}, pageOffset = 1 }
        for key, item in pairs(overrides) do
          value[key] = item
        end
        return value
      end
      local fresh = plan.compute(catalogState({}))
      lu.assertTrue(fresh.ok)
      lu.assertEquals(fresh.appendKeys, { "a/one", "a/two" })

      local complete = plan.compute(catalogState({
        titles = { "Materials", "Goods", "Stats", "Ledger", "One", "Two" },
        childCount = 5,
        pageIndex = { ["a/one"] = 3, ["a/two"] = 4 },
      }))
      lu.assertTrue(complete.ok)
      lu.assertEquals(complete.appendKeys, {})

      -- Without the offset the same menu is refused: the page count and the page positions do not match titles.
      local wrong = plan.compute(catalogState({ pageOffset = 0 }))
      lu.assertFalse(wrong.ok)
      lu.assertStrContains(wrong.reason, "tab titles but")
      local shifted = plan.compute(catalogState({
        titles = { "Materials", "Goods", "Stats", "Ledger", "One" },
        childCount = 4,
        pageIndex = { ["a/one"] = 4 }, -- a title-based position (offset 0) is not the page position here
      }))
      lu.assertFalse(shifted.ok)
      lu.assertStrContains(shifted.reason, "something else")
    end,

    testRefreshDuringABuildIsRefused = function()
      local logs, ran = {}, 0
      local gate = plan.newGate(function(text)
        logs[#logs + 1] = text
      end)
      local entry = { owner = "a", title = "One" }
      gate:run(function()
        lu.assertFalse(gate:request(entry, function()
          ran = ran + 1
        end))
      end)
      lu.assertEquals(ran, 0)
      lu.assertEquals(#logs, 1)
      lu.assertTrue(gate:request(entry, function()
        ran = ran + 1
      end))
      lu.assertEquals(ran, 1)
    end,
  },
}
