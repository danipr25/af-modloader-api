-- Contract of the tab widget click hook in tabs.lua: each router (the V menu's and the TAB menu's) registers
-- WBP_TagSwitcher_C:OnMouseButtonDown exactly once, however many arrows and marks ask for it, and again only when the
-- game loaded the class again. The game is replaced by fakes for RegisterHook and ExecuteInGameThread.
local lu = require("luaunit")
local tabs = require("tabs")
local ui = require("ui")

local HOOK = ui.CLASS.tagSwitcher .. ":OnMouseButtonDown"
local GLOBALS =
  { "RegisterHook", "ExecuteInGameThread", "StaticFindObject", "StaticConstructObject", "FText", "FindFirstOf" }

local saved, registered, logs

local function classAt(address)
  return {
    GetAddress = function()
      return address
    end,
  }
end

local function newMenu(menu)
  return tabs.new({
    registry = {},
    log = function(text)
      logs[#logs + 1] = text
    end,
    menu = menu,
  })
end

local function hooksOf(path)
  local count = 0
  for _, entry in ipairs(registered) do
    if entry.path == path then
      count = count + 1
    end
  end
  return count
end

-- A widget that answers every call with another such widget, is valid and has a stable address.
local nextId
local function proxy()
  nextId = nextId + 1
  local id = nextId
  local object = {}
  return setmetatable(object, {
    __index = function(self, name)
      local value
      if name == "IsValid" then
        value = function()
          return true
        end
      elseif name == "GetAddress" then
        value = function()
          return id
        end
      else
        value = proxy()
      end
      rawset(self, name, value)
      return value
    end,
    __call = function()
      return proxy()
    end,
  })
end

local function fakeRegisterHook(path, fn)
  registered[#registered + 1] = { path = path, fn = fn }
end

return {
  TestSwitcherHook = {
    setUp = function()
      saved, registered, logs = {}, {}, {}
      for _, name in ipairs(GLOBALS) do
        saved[name] = _G[name]
      end
      _G.ExecuteInGameThread = function(fn)
        fn()
      end
      _G.RegisterHook = fakeRegisterHook
      nextId = 0
      local class = proxy()
      _G.StaticFindObject = function()
        return class
      end
      _G.StaticConstructObject = proxy
      _G.FText = function(text)
        return text
      end
      _G.FindFirstOf = proxy
    end,
    tearDown = function()
      for _, name in ipairs(GLOBALS) do
        _G[name] = saved[name]
      end
    end,

    testArrowsAndMarksShareOneHookPerRouter = function()
      local tab = newMenu(tabs.TAB_MENU)
      local catalog = newMenu(tabs.CATALOG_MENU)
      -- The real call site of the arrows: Bar:ensureArrows.
      local geometry = { overlay = proxy(), box = proxy(), padding = { Left = 0.0 }, translationY = 0.0 }
      tab.bar:ensureArrows({ panel = proxy(), tree = proxy() }, { geometry = geometry, logged = {} })
      -- The real wiring of the marks: the ctx Tabs:fill gives to ui.newPage, on both menus.
      local original = ui.newPage
      local contexts = {}
      ui.newPage = function(ctx)
        contexts[#contexts + 1] = ctx
        return { text = function() end }, { alive = true, inputs = {} }
      end
      for _, menu in ipairs({ tab, catalog }) do
        local record = { entry = { owner = "m", title = "T", build = function() end }, root = proxy() }
        menu:fill({ panel = proxy(), tree = proxy(), pages = {} }, record)
      end
      ui.newPage = original
      lu.assertEquals(#contexts, 2)
      -- Arrows and marks of the TAB menu ask for the same class, and so do the catalog's marks: one hook each.
      local class = _G.StaticFindObject()
      contexts[1].onMarkCreated(class)
      contexts[2].onMarkCreated(class)
      contexts[2].onMarkCreated(class)
      lu.assertEquals(hooksOf(HOOK), 2)
    end,

    testAClickIsRoutedOnlyToTheRouterThatOwnsTheWidget = function()
      local tab = newMenu(tabs.TAB_MENU)
      local catalog = newMenu(tabs.CATALOG_MENU)
      local open = {
        IsValid = function()
          return true
        end,
      }
      tab.state = { active = true, panel = open, pages = {} }
      catalog.state = { active = true, panel = open, pages = {} }
      local ran = {}
      tab.clicks:register(1, {
        owner = "m",
        fn = function()
          ran[#ran + 1] = "tab"
        end,
      })
      catalog.clicks:register(2, {
        owner = "m",
        fn = function()
          ran[#ran + 1] = "catalog"
        end,
      })
      local class = proxy()
      tab:ensureSwitcherHook(class)
      catalog:ensureSwitcherHook(class)
      lu.assertEquals(#registered, 2)
      local function context(address)
        local widget = {
          GetAddress = function()
            return address
          end,
        }
        return {
          get = function()
            return widget
          end,
        }
      end
      for _, entry in ipairs(registered) do
        entry.fn(context(1))
      end
      lu.assertEquals(ran, { "tab" })
      ran = {}
      for _, entry in ipairs(registered) do
        entry.fn(context(2))
      end
      lu.assertEquals(ran, { "catalog" })
    end,

    testTheHookIsRegisteredAgainOnlyWhenTheClassIsLoadedAgain = function()
      local catalog = newMenu(tabs.CATALOG_MENU)
      catalog:ensureSwitcherHook(classAt(10))
      catalog:ensureSwitcherHook(classAt(10))
      lu.assertEquals(hooksOf(HOOK), 1)
      catalog:ensureSwitcherHook(classAt(11))
      lu.assertEquals(hooksOf(HOOK), 2)
      lu.assertEquals(#logs, 3) -- hooked, class loaded again, hooked
    end,

    testAFailedRegistrationIsTriedAgainAndLoggedOnce = function()
      local catalog = newMenu(tabs.CATALOG_MENU)
      _G.RegisterHook = function()
        error("not available")
      end
      catalog:ensureSwitcherHook(classAt(10))
      catalog:ensureSwitcherHook(classAt(10))
      local failures = 0
      for _, line in ipairs(logs) do
        if line:find("could not hook", 1, true) then
          failures = failures + 1
        end
      end
      lu.assertEquals(failures, 1)
      _G.RegisterHook = fakeRegisterHook
      catalog:ensureSwitcherHook(classAt(10))
      lu.assertEquals(hooksOf(HOOK), 1)
    end,
  },
}
