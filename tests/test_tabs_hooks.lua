-- Contract of the tab widget click hook in tabs.lua: each router (the V menu's and the TAB menu's) registers
-- WBP_TagSwitcher_C:OnMouseButtonDown exactly once, however many arrows and marks ask for it, and again only when the
-- game loaded the class again. The game is replaced by fakes for RegisterHook and ExecuteInGameThread.
local lu = require("luaunit")
local tabs = require("tabs")
local ui = require("ui")

local HOOK = ui.CLASS.tagSwitcher .. ":OnMouseButtonDown"
local GLOBALS = { "RegisterHook", "ExecuteInGameThread" }

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
    end,
    tearDown = function()
      for _, name in ipairs(GLOBALS) do
        _G[name] = saved[name]
      end
    end,

    testArrowsAndMarksShareOneHookPerRouter = function()
      local tab = newMenu(tabs.TAB_MENU)
      local catalog = newMenu(tabs.CATALOG_MENU)
      local class = classAt(10)
      -- The TAB menu's tab bar asks through its own option, the marks of both menus through the page context.
      tab.bar.ensureHook(class)
      tab:ensureSwitcherHook(class)
      catalog:ensureSwitcherHook(class)
      catalog:ensureSwitcherHook(class)
      lu.assertEquals(hooksOf(HOOK), 2) -- one per router
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
