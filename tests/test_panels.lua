-- Contract of the side tabs on the cauldron panel (panels.lua): the structure is built once per panel instance, the
-- tabs switch between the game's content and a mod page, the page never outlives its panel, and clicks and the input
-- polling only work while the panel is open. The game is replaced by a small fake UMG with a parent/child tree; how
-- it looks in game is not tested here.
local lu = require("luaunit")
local panels = require("panels")
local registry = require("registry")
local ui = require("ui")

local PANEL_CLASS = "/Game/Blueprints/WBP/FurnitureInfo/WBP_CauldronPanel.WBP_CauldronPanel_C"
local OPEN_HOOK = PANEL_CLASS .. ":PostSetContextActor"
local CLOSE_HOOK = PANEL_CLASS .. ":BP_OnDeactivated"
local BUTTON_HOOK = "/Script/CommonUI.CommonButtonBase:HandleButtonClicked"
local SWITCHER_HOOK = ui.CLASS.tagSwitcher .. ":OnMouseButtonDown"
local Z_TREE = "/Game/Blueprints/WBP/SkillPointPanel/WBP_SkillPointPanel.WBP_SkillPointPanel_C:WidgetTree."
local VISIBLE, COLLAPSED = 0, 1

local GLOBALS = {
  "StaticFindObject",
  "StaticConstructObject",
  "FText",
  "FName",
  "FindFirstOf",
  "RegisterHook",
  "ExecuteInGameThread",
  "ExecuteWithDelay",
  "LoopInGameThreadWithDelay",
  "CancelDelayedAction",
  "RegisterInitGameStatePostHook",
  "LoadAsset",
}

local fake, reg, mod, api

-- ---------------------------------------------------------------------------------------------------------------
-- The fake UMG

local function shortName(class)
  return (class:match("[%.:]([%w_]+)$")) or class
end

local SUB_WIDGETS = { ContentBorder = true, Txt_Title = true, Txt_Title_Highlight = true, WidgetTree = true }

local function detach(child)
  local parent = child.parent
  if parent then
    if parent.content == child then
      parent.content = false
    end
    for index, other in ipairs(parent.children) do
      if other == child then
        table.remove(parent.children, index)
        break
      end
    end
    child.parent = false
  end
end

local function attach(parent, child)
  detach(child)
  child.parent = parent
  parent.children[#parent.children + 1] = child
end

local newWidget
local METHODS = {
  IsValid = function(self)
    return self.valid
  end,
  GetAddress = function(self)
    return self.address
  end,
  GetClass = function(self)
    return {
      GetFName = function()
        return {
          ToString = function()
            return self.className or shortName(self.class)
          end,
        }
      end,
    }
  end,
  SetVisibility = function(self, value)
    self.visibility = value
  end,
  SetText = function(self, text)
    self.text = text
  end,
  GetText = function(self)
    return {
      ToString = function()
        return self.text or ""
      end,
    }
  end,
  SetContent = function(self, child)
    attach(self, child)
    self.content = child
  end,
  GetContent = function(self)
    return self.content or self.children[1]
  end,
  GetParent = function(self)
    return self.parent
  end,
  RemoveFromParent = function(self)
    detach(self)
  end,
  GetChildAt = function(self, index)
    return self.children[index + 1]
  end,
  ClearChildren = function(self)
    for _, child in ipairs(self.children) do
      child.parent = false
    end
    self.children = {}
    self.content = false
  end,
}
for _, name in ipairs({ "AddChild", "AddChildToOverlay", "AddChildToVerticalBox", "AddChildToHorizontalBox" }) do
  METHODS[name] = function(self, child)
    attach(self, child)
    return newWidget("slot")
  end
end

newWidget = function(class)
  local widget = {
    class = class,
    calls = {},
    address = #fake.widgets + 1,
    children = {},
    valid = true,
    -- Plain fields start false: an unset field of a widget would answer like a method.
    parent = false,
    content = false,
    className = false,
    text = false,
    visibility = false,
  }
  fake.widgets[#fake.widgets + 1] = widget
  return setmetatable(widget, {
    __index = function(self, name)
      if METHODS[name] then
        return METHODS[name]
      end
      if SUB_WIDGETS[name] then
        local child = newWidget(name)
        rawset(self, name, child)
        return child
      end
      return function(target, ...)
        target.calls[#target.calls + 1] = { name = name, args = { ... } }
      end
    end,
  })
end

local function widgetsOfClass(class)
  local found = {}
  for _, widget in ipairs(fake.widgets) do
    if widget.class == class then
      found[#found + 1] = widget
    end
  end
  return found
end

-- A cauldron panel as the game builds it: root [title box, body SizeBox > Border > content VerticalBox].
local function newPanel(actorClass)
  local panel = newWidget("panel")
  local root = newWidget("root")
  local body = newWidget("body")
  local border = newWidget("border")
  local content = newWidget("/Script/UMG.VerticalBox")
  root:AddChildToVerticalBox(newWidget("titleBox"))
  root:AddChildToVerticalBox(body)
  body:AddChild(border)
  border:SetContent(content)
  panel.WidgetTree = { RootWidget = root }
  panel.Txt_FacilityTitle = newWidget("title")
  panel.Txt_FacilityTitle.text = "Pewter Cauldron"
  local actor = newWidget("actor")
  actor.className = actorClass
  panel.ContextActor = actor
  panel.CauldronComp = newWidget("component")
  panel.game = { content = content, border = border, body = body, root = root }
  return panel
end

local function setupGame()
  fake = { widgets = {}, saved = {}, logs = {}, hooks = {}, missing = {}, loops = {}, cancelled = 0 }
  for _, name in ipairs(GLOBALS) do
    fake.saved[name] = _G[name]
  end
  local templates = {
    [Z_TREE .. "SizeBox_71"] = { WidthOverride = 128.0, bOverride_HeightOverride = true, HeightOverride = 92.0 },
    [Z_TREE .. "Border_110"] = { Background = "art", Padding = "padding" },
    [Z_TREE .. "CommonTextBlock_122"] = { Style = "style" },
    [Z_TREE .. "ScaleBox_1"] = { Stretch = 2, UserSpecifiedScale = 1.0 },
  }
  _G.StaticFindObject = function(path)
    if fake.missing[path] or (fake.missingZ and path:find(Z_TREE, 1, true)) then
      return nil
    end
    local object = templates[path] or {}
    object.path = path
    object.IsValid = function()
      return true
    end
    object.Create = function(_, _, class)
      local kind = class.path == ui.CLASS.tagSwitcher and "switcher" or "tile"
      if class.path == ui.CLASS.button then
        kind = "button"
      end
      return newWidget(kind)
    end
    return object
  end
  _G.StaticConstructObject = function(class)
    return newWidget(class.path)
  end
  _G.FText = function(text)
    return text
  end
  _G.FName = function(text)
    return text
  end
  _G.FindFirstOf = function()
    return newWidget("controller")
  end
  _G.LoadAsset = function() end
  _G.RegisterHook = function(path, fn)
    fake.hooks[#fake.hooks + 1] = { path = path, fn = fn }
  end
  _G.ExecuteInGameThread = function(fn)
    fn()
  end
  _G.ExecuteWithDelay = function() end
  _G.LoopInGameThreadWithDelay = function(_, fn)
    fake.loops[#fake.loops + 1] = fn
    return #fake.loops
  end
  _G.CancelDelayedAction = function(handle)
    fake.cancelled = fake.cancelled + 1
    fake.loops[handle] = false
  end
  _G.RegisterInitGameStatePostHook = function(fn)
    fake.worldHook = fn
  end
end

local function restoreGame()
  for _, name in ipairs(GLOBALS) do
    _G[name] = fake.saved[name]
  end
end

local function hooksAt(path)
  local found = {}
  for _, hook in ipairs(fake.hooks) do
    if hook.path == path then
      found[#found + 1] = hook
    end
  end
  return found
end

-- Calls the game's hook the way UE4SS does: the hooked object arrives wrapped.
local function fire(path, object)
  local hooks = hooksAt(path)
  lu.assertTrue(#hooks > 0, "no hook registered for " .. path)
  for _, hook in ipairs(hooks) do
    hook.fn({
      get = function()
        return object
      end,
    })
  end
end

local function logsWith(text)
  local count = 0
  for _, line in ipairs(fake.logs) do
    if line:find(text, 1, true) then
      count = count + 1
    end
  end
  return count
end

local function tick()
  for _, fn in ipairs(fake.loops) do
    if fn then
      fn()
    end
  end
end

-- The registry and the module wired like main.lua does it, with one tab whose build is recorded in `built`.
local built
local function setupMod(extra)
  reg = registry.new({
    selfId = "af-modloader-api",
    version = "0.1.4",
    log = function(text)
      fake.logs[#fake.logs + 1] = text
    end,
  })
  mod = panels.new({ registry = reg, log = reg.log })
  reg.onPanelTabAdded = function()
    mod:install()
  end
  reg.onPanelTabRefresh = function(entry)
    mod:refresh(entry)
  end
  api = reg:use({
    modId = "recipes",
    log = function() end,
  })
  built = {}
  local spec = {
    id = "fav",
    title = "Recipes",
    build = function(page, info)
      local record = { page = page, info = info }
      built[#built + 1] = record
      page:text("hello")
      if extra then
        extra(page, info, record)
      end
    end,
  }
  return api.panels.tab(spec)
end

local function open(panel)
  fire(OPEN_HOOK, panel)
end

local function close(panel)
  fire(CLOSE_HOOK, panel)
end

-- The tab widgets of the current panel state: [1] is "Cauldron", then the mod tabs in order.
local function clickTab(index)
  fire(SWITCHER_HOOK, mod.state.tabs[index].click)
end

return {
  TestCauldronPanelTabs = {
    setUp = setupGame,
    tearDown = restoreGame,

    testHooksAreRegisteredOnceHoweverManyTabsAreAdded = function()
      setupMod()
      api.panels.tab({ id = "second", title = "Other", build = function() end })
      lu.assertEquals(#hooksAt(OPEN_HOOK), 1)
      lu.assertEquals(#hooksAt(CLOSE_HOOK), 1)
      lu.assertEquals(#hooksAt(BUTTON_HOOK), 1)
    end,

    testStructureIsBuiltOncePerPanelInstance = function()
      setupMod()
      local panel = newPanel("BP_PewterCauldron_C")
      open(panel)
      lu.assertEquals(#mod.state.tabs, 2)
      local tabsBox = mod.state.tabsBox
      local count = #fake.widgets
      close(panel)
      open(panel)
      lu.assertIs(mod.state.tabsBox, tabsBox)
      lu.assertEquals(#fake.widgets, count)
      lu.assertEquals(logsWith("cauldron panel: added 1 side tab(s)"), 1)
      -- The game's content now sits in our overlay inside the border, and the body in the outer overlay.
      lu.assertIs(panel.game.border:GetContent(), mod.state.inner)
      lu.assertIs(panel.game.content.parent, mod.state.inner)
      lu.assertIs(panel.game.body.parent, mod.state.outer)
      -- A new panel instance (after loading a save) gets its own structure.
      local other = newPanel("BP_SilverCauldron_C")
      open(other)
      lu.assertEquals(mod.state.panel, other)
      lu.assertEquals(mod.state.kind, "advanced")
      lu.assertEquals(logsWith("cauldron panel: added 1 side tab(s)"), 2)
    end,

    testAnUnknownCauldronGetsNoTabsAndOneLogLine = function()
      setupMod()
      local panel = newPanel("BP_SomethingNew_C")
      open(panel)
      close(panel)
      open(panel)
      lu.assertEquals(panel.game.border:GetContent(), panel.game.content)
      lu.assertEquals(logsWith("BP_SomethingNew_C"), 1)
      lu.assertEquals(#built, 0)
    end,

    testMissingZTemplatesLeaveThePanelAlone = function()
      setupMod()
      fake.missingZ = true
      local panel = newPanel("BP_PewterCauldron_C")
      open(panel)
      open(panel)
      lu.assertEquals(panel.game.border:GetContent(), panel.game.content)
      lu.assertEquals(panel.game.body.parent, panel.game.root)
      lu.assertEquals(logsWith("no side tabs on the cauldron panel"), 1)
    end,

    testSwitchingTabsShowsThePageAndBackRestoresTheGame = function()
      setupMod()
      local panel = newPanel("BP_SilverCauldron_C")
      open(panel)
      lu.assertEquals(panel.game.content.visibility, VISIBLE)
      lu.assertEquals(mod.state.pageHolder.visibility, COLLAPSED)
      clickTab(2)
      lu.assertEquals(#built, 1)
      local info = built[1].info
      lu.assertEquals(info.kind, "advanced")
      lu.assertIs(info.actor, panel.ContextActor)
      lu.assertIs(info.component, panel.CauldronComp)
      lu.assertTrue(info.isCurrent())
      lu.assertEquals(panel.game.content.visibility, COLLAPSED)
      lu.assertEquals(mod.state.pageHolder.visibility, VISIBLE)
      lu.assertEquals(panel.Txt_FacilityTitle.text, "Recipes")
      local session = mod.state.session
      lu.assertTrue(session.alive)
      -- Back to the Cauldron tab through the tab, and again through the page's own info.showGame().
      clickTab(1)
      lu.assertFalse(session.alive)
      lu.assertEquals(panel.game.content.visibility, VISIBLE)
      lu.assertEquals(panel.Txt_FacilityTitle.text, "Pewter Cauldron")
      lu.assertEquals(#mod.state.pageRoot.children, 0)
      clickTab(2)
      lu.assertEquals(#built, 2)
      built[2].info.showGame()
      lu.assertEquals(panel.game.content.visibility, VISIBLE)
      lu.assertNil(mod.state.showing)
    end,

    testAFailingBuildLeavesAPageSayingSo = function()
      setupMod(function()
        error("boom")
      end)
      open(newPanel("BP_PewterCauldron_C"))
      clickTab(2)
      lu.assertEquals(logsWith("failed to build"), 1)
      lu.assertTrue(mod.state.session.alive)
    end,

    testClosingKillsThePageAndStopsThePolling = function()
      local typed = {}
      setupMod(function(page)
        page:input({
          onChange = function(text)
            typed[#typed + 1] = text
          end,
        })
      end)
      local panel = newPanel("BP_PewterCauldron_C")
      open(panel)
      clickTab(2)
      local session = mod.state.session
      lu.assertEquals(#fake.loops, 1)
      local box = widgetsOfClass(ui.CLASS.edit)[1]
      box.text = "ruby"
      tick()
      lu.assertEquals(typed, { "ruby" })
      close(panel)
      lu.assertFalse(session.alive)
      lu.assertEquals(fake.cancelled, 1)
      lu.assertFalse(fake.loops[1])
      box.text = "ruby2"
      tick()
      lu.assertEquals(typed, { "ruby" })
      lu.assertEquals(panel.game.content.visibility, VISIBLE)
      lu.assertEquals(panel.Txt_FacilityTitle.text, "Pewter Cauldron")
    end,

    testOpeningAgainStartsOnTheCauldronTabAndOldInfoIsNoLongerCurrent = function()
      setupMod()
      local panel = newPanel("BP_PewterCauldron_C")
      open(panel)
      clickTab(2)
      local info = built[1].info
      -- The game reuses the panel for another cauldron without a close in between.
      panel.ContextActor.className = "BP_SilverCauldron_C"
      open(panel)
      lu.assertEquals(panel.game.content.visibility, VISIBLE)
      lu.assertNil(mod.state.showing)
      lu.assertFalse(info.isCurrent())
      lu.assertEquals(mod.state.kind, "advanced")
    end,

    testInfoIsNotCurrentOnAnotherActorOrAfterClose = function()
      setupMod()
      local panel = newPanel("BP_PewterCauldron_C")
      open(panel)
      clickTab(2)
      local info = built[1].info
      lu.assertTrue(info.isCurrent())
      local actor = panel.ContextActor
      panel.ContextActor = newWidget("actor2")
      lu.assertFalse(info.isCurrent())
      panel.ContextActor = actor
      lu.assertTrue(info.isCurrent())
      close(panel)
      lu.assertFalse(info.isCurrent())
    end,

    testClicksOnThePageReachTheModOnlyWhileThePanelIsOpen = function()
      local clicked = 0
      setupMod(function(page)
        page:row():button("Go", function()
          clicked = clicked + 1
        end)
      end)
      local panel = newPanel("BP_PewterCauldron_C")
      open(panel)
      clickTab(2)
      local button = widgetsOfClass("button")[1]
      fire(BUTTON_HOOK, button)
      lu.assertEquals(clicked, 1)
      close(panel)
      fire(BUTTON_HOOK, button)
      lu.assertEquals(clicked, 1)
      -- Open again: the old page is gone, so the old button no longer reacts either.
      open(panel)
      fire(BUTTON_HOOK, button)
      lu.assertEquals(clicked, 1)
    end,

    testRefreshRebuildsOnlyTheTabThatIsShowing = function()
      local tab = setupMod()
      local panel = newPanel("BP_PewterCauldron_C")
      open(panel)
      tab:refresh()
      lu.assertEquals(#built, 0)
      clickTab(2)
      lu.assertEquals(#built, 1)
      local first = mod.state.session
      tab:refresh()
      lu.assertEquals(#built, 2)
      lu.assertFalse(first.alive)
      clickTab(1)
      tab:refresh()
      lu.assertEquals(#built, 2)
    end,

    testRefreshInsideBuildIsRefused = function()
      local tab
      tab = setupMod(function()
        tab:refresh()
      end)
      open(newPanel("BP_PewterCauldron_C"))
      clickTab(2)
      lu.assertEquals(#built, 1)
      lu.assertEquals(logsWith("was ignored because a page is being built"), 1)
    end,

    testALeftWorldDropsEverythingAndNothingIsTouchedAfter = function()
      setupMod(function(page)
        page:input({ onChange = function() end })
      end)
      local panel = newPanel("BP_PewterCauldron_C")
      open(panel)
      clickTab(2)
      local session = mod.state.session
      fake.worldHook()
      lu.assertNil(mod.state)
      lu.assertFalse(session.alive)
      lu.assertEquals(fake.cancelled, 1)
      -- A close that arrives for the dead panel afterwards does nothing.
      close(panel)
      lu.assertEquals(#built, 1)
    end,
  },
}
