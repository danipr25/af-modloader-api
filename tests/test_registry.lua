-- Contract of the registry: who may register what, and how mistakes are reported.
local lu = require("luaunit")
local registry = require("registry")

local function newRegistry()
  local logs = {}
  local reg = registry.new({
    selfId = "af-modloader-api",
    version = "0.1.0",
    log = function(text)
      logs[#logs + 1] = text
    end,
  })
  return reg, logs
end

local function fakeAF(modId)
  return {
    modId = modId,
    log = function() end,
  }
end

local function command(name)
  return {
    name = name,
    help = "does something",
    run = function() end,
  }
end

local function tabSpec(id, title)
  return {
    id = id,
    title = title,
    build = function() end,
  }
end

return {
  TestUse = {
    testNeedsTheModsAFTable = function()
      local reg = newRegistry()
      lu.assertErrorMsgContains("needs your mod's AF table", reg.use, reg, nil)
      lu.assertErrorMsgContains("needs your mod's AF table", reg.use, reg, {})
      lu.assertErrorMsgContains("needs your mod's AF table", reg.use, reg, { modId = "x" })
    end,

    testHandleIsReadOnlyAndCarriesTheVersion = function()
      local reg = newRegistry()
      local api = reg:use(fakeAF("recipes"))
      lu.assertEquals(api.version, "0.1.0")
      lu.assertErrorMsgContains("read-only", function()
        api.version = "9.9.9"
      end)
      lu.assertErrorMsgContains("read-only", function()
        api.tabs.add = nil
      end)
    end,
  },

  TestWorld = {
    testOnEnterKeepsRegistrationOrderAndOwner = function()
      local reg = newRegistry()
      local a, b = reg:use(fakeAF("mod-a")), reg:use(fakeAF("mod-b"))
      local function first() end
      local function second() end
      a.world.onEnter(first)
      b.world.onEnter(second)
      local list = reg:worldCallbacks()
      lu.assertEquals({ list[1].owner, list[2].owner }, { "mod-a", "mod-b" })
      lu.assertIs(list[1].fn, first)
      lu.assertIs(list[2].fn, second)
    end,

    testOnEnterNeedsAFunctionAndIsSealed = function()
      local reg = newRegistry()
      local api = reg:use(fakeAF("recipes"))
      lu.assertErrorMsgContains("needs a function", api.world.onEnter, "nope")
      reg:seal()
      lu.assertErrorMsgContains("entrypoint", api.world.onEnter, function() end)
    end,

    testCurrentIsNilUntilTheGameSideProvidesIt = function()
      local reg = newRegistry()
      local api = reg:use(fakeAF("recipes"))
      lu.assertNil(api.world.current())
      reg.worldCurrent = function()
        return { title = "A_1", key = "A_1", generation = 1 }
      end
      lu.assertEquals(api.world.current(), { title = "A_1", key = "A_1", generation = 1 })
      lu.assertErrorMsgContains("read-only", function()
        api.world.current = nil
      end)
    end,
  },

  TestCommandNames = {
    testValidAndInvalidNames = function()
      local cases = {
        { "recipes.unlockall", true },
        { "my-mod.do_it.now", true },
        { "abc.x1", true },
        { "Recipes.hello", false }, -- uppercase
        { "recipes", false }, -- no namespace
        { "ab.hello", false }, -- namespace shorter than 3
        { "r.hello", false }, -- would clash with engine variables
        { "recipes.", false },
        { "recipes..x", false },
        { ".hello", false },
        { "recipes.hel lo", false },
        { "recipes.hello!", false },
        { "", false },
      }
      for _, case in ipairs(cases) do
        local problem = registry.commandNameProblem(case[1], "recipes", "af-modloader-api")
        lu.assertEquals(problem == nil, case[2], "name: " .. case[1] .. " -> " .. tostring(problem))
      end
    end,

    testAfNamespaceIsReservedForTheApi = function()
      lu.assertNotNil(registry.commandNameProblem("af.thing", "recipes", "af-modloader-api"))
      lu.assertNil(registry.commandNameProblem("af.thing", "af-modloader-api", "af-modloader-api"))
    end,

    testMenuOptionIsValidatedAndTabsAreFilteredByMenu = function()
      local reg, logs = newRegistry()
      local api = reg:use(fakeAF("recipes"))
      local catalogSpec = tabSpec("vmenu", "Recipes")
      catalogSpec.menu = "catalog"
      api.tabs.add(catalogSpec)
      api.tabs.add(tabSpec("other", "Other")) -- no menu: the TAB menu
      local tabMenuSpec = tabSpec("explicit", "Explicit")
      tabMenuSpec.menu = "tab"
      api.tabs.add(tabMenuSpec)
      lu.assertEquals(#reg:tabs(), 3)
      lu.assertEquals(#reg:tabs("catalog"), 1)
      lu.assertEquals(reg:tabs("catalog")[1].key, "recipes/vmenu")
      lu.assertEquals(#reg:tabs("tab"), 2)

      for _, bad in ipairs({ "TAB", "v", "", 3, true }) do
        local spec = tabSpec("bad", "Bad")
        spec.menu = bad
        lu.assertErrorMsgContains("'menu' must be", api.tabs.add, spec)
      end
      -- The game's own titles are per menu.
      local materials = tabSpec("mat", "Materials")
      materials.menu = "catalog"
      lu.assertErrorMsgContains("game's own tabs", api.tabs.add, materials)
      api.tabs.add(tabSpec("mat", "Materials")) -- fine in the TAB menu
      -- Titles are unique across both menus.
      local clash = tabSpec("clash", "Recipes")
      clash.menu = "catalog"
      local before = #reg:tabs()
      reg:use(fakeAF("other")).tabs.add(clash) -- refused and logged, the mod keeps an inert tab
      lu.assertEquals(#reg:tabs(), before)
      lu.assertEquals(#logs, 1)
      lu.assertStrContains(logs[1], "already uses that title")
    end,

    testSelectIsForwardedAndInertTabsReturnFalse = function()
      local reg = newRegistry()
      local selected = {}
      reg.onTabSelect = function(entry)
        selected[#selected + 1] = entry.key
        return true
      end
      local api = reg:use(fakeAF("recipes"))
      local spec = tabSpec("main", "Recipes")
      spec.menu = "catalog"
      local tab = api.tabs.add(spec)
      lu.assertTrue(tab:select())
      lu.assertEquals(selected, { "recipes/main" })
      local refused = api.tabs.add(tabSpec("main", "Other title")) -- duplicate id: inert
      lu.assertFalse(refused:select())
      local bare = newRegistry():use(fakeAF("recipes")).tabs.add(tabSpec("main", "Recipes"))
      lu.assertFalse(bare:select()) -- no game module connected
    end,

    testSectionsAreValidatedAndSealedLikeTabs = function()
      local reg, logs = newRegistry()
      local api = reg:use(fakeAF("recipes"))
      local function section(id)
        return { id = id, build = function() end }
      end
      lu.assertTrue(api.catalog.section(section("cauldron")))
      lu.assertEquals(#reg:sections(), 1)
      lu.assertEquals(reg:sections()[1].key, "recipes/cauldron")
      lu.assertFalse(api.catalog.section(section("cauldron"))) -- duplicate: refused and logged, the mod keeps running
      lu.assertEquals(#logs, 1)
      lu.assertTrue(reg:use(fakeAF("other")).catalog.section(section("cauldron"))) -- ids are per mod
      lu.assertErrorMsgContains("catalog.section needs a table", api.catalog.section, nil)
      lu.assertErrorMsgContains("'id' must be", api.catalog.section, section("Bad Id"))
      lu.assertErrorMsgContains("'build' must be", api.catalog.section, { id = "x" })
      reg:seal()
      lu.assertErrorMsgContains("too late", api.catalog.section, section("late"))
    end,

    testBadSpecRaisesAClearError = function()
      local api = newRegistry():use(fakeAF("recipes"))
      lu.assertErrorMsgContains("console.add needs a table", api.console.add, nil)
      lu.assertErrorMsgContains("lowercase", api.console.add, command("Recipes.Hello"))
      lu.assertErrorMsgContains("'help'", api.console.add, { name = "recipes.hello", run = function() end })
      lu.assertErrorMsgContains("'run'", api.console.add, { name = "recipes.hello", help = "x" })
      lu.assertErrorMsgContains("game's own tabs", api.tabs.add, tabSpec("main", "World"))
    end,
  },

  TestDuplicates = {
    testSecondModWithTheSameCommandIsRefusedAndLogged = function()
      local reg, logs = newRegistry()
      local first = reg:use(fakeAF("recipes"))
      local second = reg:use(fakeAF("other"))
      lu.assertTrue(first.console.add(command("recipes.hello")))
      lu.assertFalse(second.console.add(command("recipes.hello")))
      lu.assertEquals(#logs, 1)
      lu.assertStrContains(logs[1], "other")
      lu.assertStrContains(logs[1], "recipes")
      lu.assertEquals(#reg:commands(), 1)
      lu.assertEquals(reg:commands()[1].owner, "recipes")
    end,

    testTabIdAndTitleMustBeUnique = function()
      local reg, logs = newRegistry()
      local first = reg:use(fakeAF("recipes"))
      local second = reg:use(fakeAF("other"))
      first.tabs.add(tabSpec("main", "Recipes"))
      local refused = first.tabs.add(tabSpec("main", "Other title"))
      second.tabs.add(tabSpec("main", "Recipes"))
      lu.assertEquals(#logs, 2)
      lu.assertEquals(#reg:tabs(), 1)
      refused:refresh() -- a refused tab is inert, it must not raise
    end,
  },

  TestOrderAndOwners = {
    testTabsKeepRegistrationOrderAndCommandsAreSortedByName = function()
      local reg = newRegistry()
      local api = reg:use(fakeAF("recipes"))
      for _, title in ipairs({ "Zeta", "Alpha", "Mid" }) do
        api.tabs.add(tabSpec(title:lower(), title))
      end
      local titles = {}
      for _, entry in ipairs(reg:tabs()) do
        titles[#titles + 1] = entry.title
      end
      lu.assertEquals(titles, { "Zeta", "Alpha", "Mid" })
      api.console.add(command("recipes.zeta"))
      api.console.add(command("recipes.alpha"))
      lu.assertEquals(reg:commands()[1].name, "recipes.alpha")
    end,

    testConsoleIsNeededOnlyByOtherModsThanTheApi = function()
      local reg = newRegistry()
      lu.assertNotNil(reg:addCommand("af-modloader-api", command("af.help")))
      lu.assertEquals(reg:consoleNeededBy(), {})
      reg:use(fakeAF("recipes")).console.add(command("recipes.hello"))
      reg:use(fakeAF("alpha")).console.add(command("alpha.hello"))
      lu.assertEquals(reg:consoleNeededBy(), { "alpha", "recipes" })
    end,
  },

  TestRegistrationWindow = {
    testRegisteringAfterTheEntrypointIsRefused = function()
      local reg = newRegistry()
      local api = reg:use(fakeAF("recipes"))
      reg:seal()
      lu.assertErrorMsgContains("too late", api.console.add, command("recipes.late"))
      lu.assertErrorMsgContains("too late", api.tabs.add, tabSpec("late", "Late"))
      lu.assertEquals(#reg:commands(), 0)
    end,

    testRefreshIsForwardedToTheGameModule = function()
      local reg = newRegistry()
      local refreshed = {}
      reg.onTabRefresh = function(entry)
        refreshed[#refreshed + 1] = entry.key
      end
      local tab = reg:use(fakeAF("recipes")).tabs.add(tabSpec("main", "Recipes"))
      tab:refresh()
      lu.assertEquals(refreshed, { "recipes/main" })
    end,
  },
  TestPanelTabs = {
    testARegisteredTabIsKeptInOrderAndForwardsRefresh = function()
      local reg = newRegistry()
      local added, refreshed = {}, {}
      reg.onPanelTabAdded = function(entry)
        added[#added + 1] = entry.key
      end
      reg.onPanelTabRefresh = function(entry)
        refreshed[#refreshed + 1] = entry.key
      end
      local tab = reg:use(fakeAF("recipes")).panels.tab(tabSpec("fav", "Favorites"))
      reg:use(fakeAF("other")).panels.tab({ id = "x", title = "Other", panel = "cauldron", build = function() end })
      lu.assertEquals(added, { "recipes/fav", "other/x" })
      lu.assertEquals(#reg:panelTabs("cauldron"), 2)
      lu.assertEquals(reg:panelTabs("cauldron")[1].title, "Favorites")
      tab:refresh()
      lu.assertEquals(refreshed, { "recipes/fav" })
      -- Panel tabs are separate from the menus' tabs.
      lu.assertEquals(#reg:tabs(), 0)
    end,

    testInvalidSpecsRaiseAnError = function()
      local api = newRegistry():use(fakeAF("recipes"))
      local cases = {
        { nil, "needs a table" },
        { { id = "a", title = "T", build = function() end, panel = "tab" }, "'panel' must be" },
        { { id = "A", title = "T", build = function() end }, "'id' must be" },
        { { id = "a", title = "", build = function() end }, "'title' must be" },
        { { id = "a", title = "T" }, "'build' must be a function(page, info)" },
        { { id = "a", title = "Cauldron", build = function() end }, "game's own tab" },
        { { id = "a", title = "  cauldron ", build = function() end }, "game's own tab" },
      }
      for _, case in ipairs(cases) do
        lu.assertErrorMsgContains(case[2], api.panels.tab, case[1])
      end
    end,

    testDuplicateIdOrTitleIsRefusedWithALogLineAndAnInertTab = function()
      local reg, logs = newRegistry()
      local api = reg:use(fakeAF("recipes"))
      api.panels.tab(tabSpec("fav", "Favorites"))
      local again = api.panels.tab(tabSpec("fav", "Another"))
      local sameTitle = reg:use(fakeAF("other")).panels.tab(tabSpec("x", "Favorites"))
      again:refresh()
      sameTitle:refresh()
      lu.assertEquals(#reg:panelTabs("cauldron"), 1)
      lu.assertEquals(#logs, 2)
      lu.assertStrContains(logs[1], "already added a panel tab with id 'fav'")
      lu.assertStrContains(logs[2], "already uses that title")
    end,

    testRegisteringAfterTheEntrypointIsRefused = function()
      local reg = newRegistry()
      local api = reg:use(fakeAF("recipes"))
      reg:seal()
      lu.assertErrorMsgContains("too late", api.panels.tab, tabSpec("late", "Late"))
      lu.assertEquals(#reg:panelTabs("cauldron"), 0)
    end,
  },

  TestDefer = {
    testRunsTheFunctionAndLogsItsErrorsWithTheModId = function()
      local reg, logs = newRegistry()
      local api = reg:use(fakeAF("recipes"))
      local ran = false
      api.defer(function()
        ran = true
      end)
      lu.assertTrue(ran)
      api.defer(function()
        error("boom")
      end)
      lu.assertStrContains(logs[1], "mod recipes: a deferred function failed")
      lu.assertErrorMsgContains("needs a function", api.defer, nil)
    end,

    testTheGameModuleDecidesWhenItRuns = function()
      local reg = newRegistry()
      local queued = {}
      reg.runDeferred = function(owner, fn)
        queued[#queued + 1] = { owner, fn }
      end
      reg:use(fakeAF("recipes")).defer(function() end)
      lu.assertEquals(#queued, 1)
      lu.assertEquals(queued[1][1], "recipes")
    end,
  },
}
