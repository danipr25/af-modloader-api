-- TAB menu tabs. Game-facing, tested in game; the decisions are in tabs_plan.lua (tested without the game).
-- The mechanism comes from docs/tab-menu.md (verified in game 1.1.5023, 2026-10-20): append the title to the tab
-- bar's TitleList, rebuild the bar with PreConstruct, add the page to the panel's WidgetSwitcher.
-- The live panel is the source of truth: every call to ensure() reads it and plans from what it finds.
-- Calls that docs/tab-menu.md does not cover are marked "unverified" and wrapped so a failure is logged, not fatal.
local clicks = require("clicks")
local hooks = require("hooks")
local loop = require("loop")
local plan = require("tabs_plan")
local tabbar = require("tabbar")
local ui = require("ui")

local PANEL_CLASS = "/Game/Blueprints/WBP/PlayerGear/WBP_PlayerGearPanel.WBP_PlayerGearPanel_C"
local GROUP_CLASS = "/Game/Blueprints/WBP/Utility/WBP_TagSwitcherGroup.WBP_TagSwitcherGroup_C"
-- Click sources (docs/widgets.md, verified in game 2026-10-21 in a spike). The tile class is not loaded at start.
local TILE_CLICK_HOOK = ui.CLASS.recipeTile .. ":OnMouseButtonDown"
local BUTTON_CLICK_HOOK = "/Script/CommonUI.CommonButtonBase:HandleButtonClicked"
local POLL_MS = 150
local FAILED_PAGE_TEXT = "This page failed to load, see UE4SS.log"

local isValid = ui.isValid
local tabs = {}
local Tabs = {}
Tabs.__index = Tabs

-- The object behind a hook parameter (UE4SS passes the "self" of a hooked function wrapped).
local function paramValue(param)
  local ok, value = pcall(function()
    return param:get()
  end)
  return ok and value or param
end

local addressOf = ui.addressOf

local function member(object, name)
  local ok, value = pcall(function()
    return object[name]
  end)
  if ok and isValid(value) then
    return value
  end
end

-- Fallback lookup when a member name is not found: the first widget of a class whose outer is the panel's tree.
-- Unverified (GetOuter, FindAllOf).
local function findInTree(className, tree)
  local ok, all = pcall(FindAllOf, className)
  if not ok or type(all) ~= "table" then
    return nil
  end
  local treeAddress = addressOf(tree)
  for _, candidate in ipairs(all) do
    local okOuter, outer = pcall(function()
      return candidate:GetOuter()
    end)
    if okOuter and isValid(outer) and addressOf(outer) == treeAddress then
      return candidate
    end
  end
end

-- The parts of the panel we need, or nil and the reason the menu does not look as expected.
local function structure(panel)
  local tree = member(panel, "WidgetTree")
  if not tree then
    return nil, "the panel has no WidgetTree"
  end
  local group = member(panel, "TagSwithcer") or findInTree("WBP_TagSwitcherGroup_C", tree)
  if not group then
    return nil, "the tab bar (TagSwithcer, a WBP_TagSwitcherGroup_C) was not found"
  end
  local switcher = member(panel, "WidgetSwitcher_0") or findInTree("WidgetSwitcher", tree)
  if not switcher then
    return nil, "the page switcher (WidgetSwitcher_0) was not found"
  end
  if not member(group, "EntryPanel") then
    return nil, "the tab bar has no EntryPanel"
  end
  local okLists = pcall(function()
    return #group.TitleList + #group.EntryList
  end)
  if not okLists then
    return nil, "the tab bar has no TitleList or EntryList"
  end
  return { tree = tree, group = group, switcher = switcher }
end

local function readTitles(group)
  local list, titles = group.TitleList, {}
  for index = 1, #list do
    titles[index] = list[index]:ToString()
  end
  return titles
end

-- Rebuilds the tab bar's buttons from TitleList (verified): clear the buttons, then let the game's PreConstruct
-- build them again.
local function rebuildBar(group)
  group.EntryPanel:ClearChildren()
  group.EntryList:Empty()
  group:PreConstruct(false)
end

-- Keeps the highlight on the page that is showing. Unverified: GetActiveWidgetIndex.
local function restoreHighlight(s, log)
  local ok, problem = pcall(function()
    s.group:SetActive(s.switcher:GetActiveWidgetIndex())
  end)
  if not ok then
    log("could not restore the highlighted tab (unverified GetActiveWidgetIndex): " .. tostring(problem))
  end
end

-- The 0-based position of a widget in the switcher, or nil when it is not a child. Unverified: GetChildIndex, and
-- GetChildAt as the fallback. Raises when neither is available.
local function childIndex(switcher, widget)
  local ok, index = pcall(function()
    return switcher:GetChildIndex(widget)
  end)
  if ok and type(index) == "number" then
    return index >= 0 and index or nil
  end
  local wanted = addressOf(widget)
  local count = switcher:GetChildrenCount()
  for position = 0, count - 1 do
    local child = switcher:GetChildAt(position)
    if isValid(child) and addressOf(child) == wanted then
      return position
    end
  end
  return nil
end

-- Cleanup on unload (AF.onUnload) ships DISABLED. UE4SS may run OnUnload off the game thread, and touching widgets
-- from another thread is unsafe (AGENTS.md section 6: unverified code ships off). The code stays for when this is
-- verified in game. While it is off, a UE4SS mods restart leaves the tabs inactive until a save is loaded again.
local CLEANUP_ENABLED = false

-- Removes the last 'count' titles of the tab bar. Unverified: TArray:RemoveAt. The game's own entries are never
-- rewritten: only our titles (always the last ones, see tabs_plan.lua) are taken off the end.
local function removeTrailingTitles(group, count)
  local list = group.TitleList
  for _ = 1, count do
    list:RemoveAt(#list)
  end
end

-- options: { registry = registry object, log = function(text) }
function tabs.new(options)
  local self = setmetatable({}, Tabs)
  self.registry = options.registry
  self.log = options.log
  self.state = nil -- the current panel: { panel, address, tree, pages = { [tab key] = { entry, root, session } } }
  self.busy = false -- our own rebuild fires the hooks again
  self.gate = plan.newGate(options.log) -- refuses tab:refresh() while a page is being built
  self.clicks = clicks.new(options.log) -- routes clicks on our buttons and tiles to the mods
  self.bar = tabbar.new({ -- pages the tab bar when the tabs do not fit; its arrows are clicked through the router
    log = options.log,
    clicks = self.clicks,
    route = function(context)
      self:routeClick(context)
    end,
  })
  self.tileHook = "none" -- "none", "requested" (handed to hooks.install), "scheduled" or "registered"
  self.disabled = false
  self.stopPolling = nil
  return self
end

function Tabs:disable(reason)
  if not self.disabled then
    self.disabled = true
    self.log(
      "AF tabs are off: the TAB menu does not look the way this version expects ("
        .. reason
        .. "). Mods that add tabs will not show them. The game was not changed."
    )
  end
end

local function killSessions(state)
  for _, record in pairs(state.pages) do
    if record.session then
      record.session.alive = false
    end
  end
end

-- Only one panel state is kept: the current panel. A different (new) panel replaces it and the old one is dropped.
function Tabs:stateFor(panel)
  local address = addressOf(panel)
  local state = self.state
  if state and state.address == address and isValid(state.panel) then
    return state
  end
  if state then
    killSessions(state)
  end
  self.clicks:reset()
  self.state = { panel = panel, address = address, pages = {} }
  return self.state
end

-- Fills a tab's page by running the mod's build function. A failing build leaves one line saying so.
function Tabs:fill(state, record)
  self.gate:run(function()
    if record.session then
      record.session.alive = false
      self.clicks:dropSession(record.session)
    end
    pcall(function()
      record.root:ClearChildren()
    end)
    local owner = record.entry.owner
    local ctx = {
      panel = state.panel,
      tree = state.tree,
      root = record.root,
      owner = owner,
      log = self.log,
      clicks = self.clicks,
      onTileCreated = function(class)
        self:ensureTileHook(class)
      end,
    }
    local page, session = ui.newPage(ctx)
    record.session = session
    local ok, problem = xpcall(record.entry.build, debug.traceback, page)
    if not ok then
      self.log(
        string.format('mod %s: the page of tab "%s" failed to build: %s', owner, record.entry.title, tostring(problem))
      )
      session.alive = false
      self.clicks:dropSession(session)
      pcall(function()
        record.root:ClearChildren()
      end)
      local failed, failedSession = ui.newPage(ctx)
      failed:text(FAILED_PAGE_TEXT)
      record.session = failedSession
    end
  end)
end

local function removePages(state)
  for key, record in pairs(state.pages) do
    if record.session then
      record.session.alive = false
    end
    if isValid(record.root) then
      pcall(function()
        record.root:RemoveFromParent() -- unverified (standard UMG)
      end)
    end
    state.pages[key] = nil
  end
end

function Tabs:apply(state, s, appendKeys)
  local byKey = self.registry.tabsByKey
  local created = {}
  local appended = 0
  local ok, problem = pcall(function()
    -- Pages first: if one cannot be created, the menu has not been given a title without a page.
    for _, key in ipairs(appendKeys) do
      local entry = byKey[key]
      local record = { entry = entry, root = ui.construct("/Script/UMG.VerticalBox", s.tree) }
      state.pages[key] = record
      created[#created + 1] = key
      self:fill(state, record)
      s.switcher:AddChild(record.root)
    end
    local titles = s.group.TitleList
    for _, key in ipairs(appendKeys) do
      titles[#titles + 1] = FText(byKey[key].title)
      appended = appended + 1
    end
    rebuildBar(s.group)
  end)
  if not ok then
    -- Put the menu back the way it was found, as far as that is possible.
    if appended > 0 then
      local okTitles, titlesProblem = pcall(function()
        removeTrailingTitles(s.group, appended)
        rebuildBar(s.group)
      end)
      if not okTitles then
        self.log(
          "could not take the new titles back out of the tab bar (unverified RemoveAt): " .. tostring(titlesProblem)
        )
      end
    end
    for _, key in ipairs(created) do
      local record = state.pages[key]
      if record and isValid(record.root) then
        pcall(function()
          record.root:RemoveFromParent()
        end)
      end
      state.pages[key] = nil
    end
    error(problem, 0)
  end
  restoreHighlight(s, self.log)
end

-- Makes sure every registered tab is in this panel exactly once. Safe to call as often as the hooks fire.
-- Returns true when the panel is as the plan expects (all the tabs are there), false when it was left as it is.
function Tabs:ensure(panel, origin)
  if self.busy or self.disabled or not isValid(panel) then
    return false
  end
  self.busy = true
  local healthy = false
  local ok, problem = pcall(function()
    local s, reason = structure(panel)
    if not s then
      self:disable(reason)
      return
    end
    local state = self:stateFor(panel)
    state.tree = s.tree

    local registered, pageIndex = {}, {}
    for _, entry in ipairs(self.registry:tabs()) do
      registered[#registered + 1] = { key = entry.key, title = entry.title }
      local record = state.pages[entry.key]
      if record and isValid(record.root) then
        pageIndex[entry.key] = childIndex(s.switcher, record.root)
      end
    end
    local result = plan.compute({
      titles = readTitles(s.group),
      childCount = s.switcher:GetChildrenCount(),
      tabs = registered,
      pageIndex = pageIndex,
    })
    if not result.ok then
      if state.refused ~= result.reason then
        state.refused = result.reason
        self.log(
          "AF tabs were not added to this TAB menu: "
            .. result.reason
            .. ". The menu was left as it is. To fix it, load the save again or restart the game."
        )
      end
      return
    end
    healthy = true
    state.refused = nil
    if #result.appendKeys == 0 then
      -- Logged on every check on purpose: this is how the in-game test sees the order the hooks fire in.
      self.log(
        string.format(
          "TAB menu check (%s): all tabs present (buttons %d, titles %d, pages %d)",
          origin,
          #s.group.EntryList,
          #s.group.TitleList,
          s.switcher:GetChildrenCount()
        )
      )
    else
      local before = string.format("buttons %d, titles %d", #s.group.EntryList, #s.group.TitleList)
      self:apply(state, s, result.appendKeys)
      self.log(
        string.format(
          "TAB menu check (%s): added %d tab(s) (before: %s; after: buttons %d, titles %d, pages %d)",
          origin,
          #result.appendKeys,
          before,
          #s.group.EntryList,
          #s.group.TitleList,
          s.switcher:GetChildrenCount()
        )
      )
    end
  end)
  self.busy = false
  if not ok then
    self.log("could not update the TAB menu: " .. tostring(problem))
  end
  return ok and healthy
end

-- Pages the tab bar for the panel that just opened, or gives the game's bar back when 'healthy' is false (the tabs
-- could not be added, so nothing may stay hidden). Never raises.
function Tabs:updateBar(panel, healthy)
  local state = self.state
  if not (state and isValid(panel) and state.address == addressOf(panel)) then
    return
  end
  local ok, problem = pcall(function()
    local s = structure(panel)
    if s then
      self.bar:update(state, s.group, healthy)
    end
  end)
  if not ok then
    self.log("could not page the TAB bar: " .. tostring(problem))
  end
end

-- tab:refresh(): rebuilds the page now if it exists. Without a page yet, the next open of the menu builds it.
-- Called while a page is being built, it is refused with a log line (see tabs_plan.lua newGate).
function Tabs:refresh(entry)
  self.gate:request(entry, function()
    local state = self.state
    local record = state and state.pages[entry.key]
    if record and isValid(state.panel) and isValid(record.root) then
      local ok, problem = pcall(function()
        self:fill(state, record)
      end)
      if not ok then
        self.log(
          string.format('mod %s: could not refresh the tab "%s": %s', entry.owner, entry.title, tostring(problem))
        )
      end
    end
  end)
end

-- Polls the text of the inputs that have an onChange, while the TAB menu is open (see docs/api.md: onChange).
function Tabs:poll()
  local state = self.state
  if not state or not state.active then
    return
  end
  if not isValid(state.panel) then
    self:stopPollingNow()
    return
  end
  for _, record in pairs(state.pages) do
    local session = record.session
    if session and session.alive then
      for _, input in ipairs(session.inputs) do
        if not session.alive then
          break -- an earlier onChange rebuilt the page
        end
        local ok, text = pcall(input.read)
        if ok and text ~= input.last then
          input.last = text
          local okCall, problem = xpcall(input.onChange, debug.traceback, text)
          if not okCall then
            self.log(string.format("mod %s: onChange failed: %s", input.owner, tostring(problem)))
          end
        end
      end
    end
  end
end

function Tabs:startPolling()
  if self.stopPolling then
    return
  end
  local stop, how = loop.start(POLL_MS, function()
    self:poll()
  end, self.log)
  if stop then
    self.stopPolling = stop
    if not self.loggedLoop then
      self.loggedLoop = true
      self.log("input onChange is polled with " .. how)
    end
  elseif not self.loggedLoopFailure then
    self.loggedLoopFailure = true
    self.log("input onChange will not work: no timed loop could be started (" .. tostring(how) .. ")")
  end
end

function Tabs:stopPollingNow()
  if self.stopPolling then
    self.stopPolling()
    self.stopPolling = nil
  end
end

-- Takes our tabs out of the live panel, so a mod restart leaves the menu as the game made it. Only the titles whose
-- pages this Lua state created are removed (tabs_plan.lua titlesToRemove), and a panel where apply never ran is
-- skipped. Disabled, see CLEANUP_ENABLED. Unverified in game (AF.onUnload, RemoveAt, RemoveFromParent).
function Tabs:cleanup()
  self:stopPollingNow()
  if self.state then
    self.state.active = false
  end
  if not CLEANUP_ENABLED then
    return
  end
  local state = self.state
  self.state = nil
  if not state or not isValid(state.panel) then
    return
  end
  local registered = {}
  for _, entry in ipairs(self.registry:tabs()) do
    registered[#registered + 1] = { key = entry.key, title = entry.title }
  end
  local pageKeys = {}
  for key, record in pairs(state.pages) do
    if isValid(record.root) then
      pageKeys[key] = true
    end
  end
  local count = #plan.titlesToRemove(registered, pageKeys)
  if count == 0 then
    return
  end
  local ok, problem = pcall(function()
    local s = structure(state.panel)
    if not s then
      return
    end
    local activeBefore = s.switcher:GetActiveWidgetIndex()
    removePages(state)
    removeTrailingTitles(s.group, count)
    if activeBefore >= s.switcher:GetChildrenCount() then
      s.switcher:SetActiveWidgetIndex(0)
    end
    rebuildBar(s.group)
    restoreHighlight(s, self.log)
  end)
  if not ok then
    self.log("could not remove the tabs from the TAB menu on unload: " .. tostring(problem))
  end
end

-- A click on a tile or a button of the game. These hooks fire for every tile and every CommonUI button in the game,
-- so anything that is not ours (or any click while the TAB menu is closed) returns at once, without a log line.
function Tabs:routeClick(context)
  local state = self.state
  local open = state ~= nil and state.active == true and isValid(state.panel)
  local address = open and addressOf(paramValue(context)) or nil
  self.clicks:route(address, open)
end

-- Registers the tile click hook once the first tile exists (its class may not have been loaded before). Called
-- after every tile creation with the tile's class: cheap once registered, and a failed registration is tried again
-- at the next tile. The registration is deferred to the game thread, out of the page build.
-- If the class was loaded again since the hook was registered (a different object, for example after a save
-- load), the hook is registered again: a hook belongs to the class object it was put on.
function Tabs:ensureTileHook(class)
  local address = addressOf(class)
  if self.tileHook == "scheduled" then
    return
  end
  if self.tileHook ~= "none" then
    if address == nil or address == self.tileHookClass then
      return
    end
    self.log("the game loaded the tile class again: hooking tile clicks again")
  end
  self.tileHook = "scheduled"
  self.tileHookClass = address
  ExecuteInGameThread(function()
    local ok, problem = pcall(RegisterHook, TILE_CLICK_HOOK, function(context)
      self:routeClick(context)
    end)
    if ok then
      self.tileHook = "registered"
      self.log("tile clicks are on: hooked " .. TILE_CLICK_HOOK)
    else
      self.tileHook = "none"
      self.tileHookClass = nil
      if not self.loggedTileHookFailure then
        self.loggedTileHookFailure = true
        self.log(
          "could not hook "
            .. TILE_CLICK_HOOK
            .. " ("
            .. tostring(problem)
            .. "). Clicks on tiles will not work until it succeeds; it is tried again the next time a tile is made."
        )
      end
    end
  end)
end

function Tabs:install()
  local registry = self.registry
  local entries = {
    {
      path = BUTTON_CLICK_HOOK,
      effect = "Buttons added by mods will not react to clicks.",
      fn = function(context)
        self:routeClick(context)
      end,
    },
    {
      path = PANEL_CLASS .. ":BP_OnActivated",
      effect = "Tabs added by mods will not appear in the TAB menu.",
      fn = function(context)
        registry:seal()
        local panel = paramValue(context)
        local healthy = self:ensure(panel, "BP_OnActivated")
        self:updateBar(panel, healthy)
        if isValid(panel) and self.state and self.state.address == addressOf(panel) then
          self.state.active = true
          self:startPolling()
        end
      end,
    },
    {
      path = PANEL_CLASS .. ":BP_OnDeactivated",
      effect = "Typing in inputs of the tabs will not be reported while the menu is closed.",
      fn = function()
        self:stopPollingNow()
        if self.state then
          self.state.active = false
        end
      end,
    },
    {
      path = GROUP_CLASS .. ":PreConstruct",
      effect = "Tabs may need one more menu open to appear.",
      fn = function(context)
        registry:seal()
        if self.busy then
          return
        end
        -- The tab bar is used by five panels: only the TAB menu's matters.
        local panel = FindFirstOf("WBP_PlayerGearPanel_C")
        local group = paramValue(context)
        if isValid(panel) and isValid(group) then
          local s = structure(panel)
          if s and addressOf(s.group) == addressOf(group) then
            self:ensure(panel, "group PreConstruct")
          end
        end
      end,
    },
  }
  -- The tile class may already be loaded at start: then its hook is registered like the others, with retries.
  -- Otherwise it waits for the first tile (ensureTileHook).
  local okFind, tileClass = pcall(StaticFindObject, ui.CLASS.recipeTile)
  if okFind and isValid(tileClass) then
    self.tileHook = "requested"
    self.tileHookClass = addressOf(tileClass)
    entries[#entries + 1] = {
      path = TILE_CLICK_HOOK,
      effect = "Tiles added by mods will not react to clicks until the next tile is made, which tries again.",
      onGiveUp = function()
        self.tileHook = "none"
        self.tileHookClass = nil
      end,
      fn = function(context)
        self:routeClick(context)
      end,
    }
  end
  hooks.install(entries, self.log)
end

return tabs
