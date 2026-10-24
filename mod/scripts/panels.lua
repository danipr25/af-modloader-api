-- Side tabs on the game's cauldron panel (api.panels.tab). Game-facing; the registration rules are in registry.lua.
-- The layout and every call below were verified in game in a probe (game 1.1.5024, 2026-10-24, see docs/widgets.md):
-- the panel's content becomes an Overlay [the game's content, our page], the tabs are copies of the Z panel's side
-- tabs placed left of the panel, and a click only hides the game's content as a whole, never one of its children.
--
-- Lifetime: the panel is reused across opens (a new one after loading a save). The structure is built once per panel
-- instance. On every open and every close the page is killed, the game's content and title are restored and the
-- "Cauldron" tab is selected, so a mod page never survives its panel. Nothing touches a game object off the game
-- thread: the input polling is a game-thread loop that stops when the panel closes or the world changes.
local hooks = require("hooks")
local loop = require("loop")
local plan = require("tabs_plan")
local registry = require("registry")
local tabs = require("tabs")
local ui = require("ui")

local PANEL_ID = "cauldron"
local PANEL_CLASS = "/Game/Blueprints/WBP/FurnitureInfo/WBP_CauldronPanel.WBP_CauldronPanel_C"
local OPEN_HOOK = PANEL_CLASS .. ":PostSetContextActor"
local CLOSE_HOOK = PANEL_CLASS .. ":BP_OnDeactivated"
local BUTTON_CLICK_HOOK = "/Script/CommonUI.CommonButtonBase:HandleButtonClicked"
-- The Z panel (Research / Upgrade) is where the side tab look comes from. Its widget templates exist after loading
-- a save without opening the panel (verified in game, 2026-10-24).
local Z_CLASS = "/Game/Blueprints/WBP/SkillPointPanel/WBP_SkillPointPanel.WBP_SkillPointPanel_C"
local Z_TREE = Z_CLASS .. ":WidgetTree."
local BORDER_CLASS = "/Script/UMG.Border"
local COMMON_TEXT_CLASS = "/Script/CommonUI.CommonTextBlock"
-- ContextActor class -> the kind of cauldron (Normal has 3 slots, Advanced 2).
local KINDS = { BP_PewterCauldron_C = "normal", BP_SilverCauldron_C = "advanced" }
local GAME_TAB = "Cauldron"
-- Picked in game with the user (2026-10-24): the tabs sit 30 lower than the panel's top, the page is 420 high.
local TAB_OFFSET_Y = 30.0
local PAGE_HEIGHT = 420.0
local POLL_MS = 150
-- The panel's background is light, so texts start dark (the same dark as the probe used).
local PAGE_TEXT_COLOR = { R = 0.022, G = 0.033, B = 0.053, A = 1.0 }
local SELECTED_TINT = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
local UNSELECTED_TINT = { R = 0.75, G = 0.75, B = 0.75, A = 1.0 }
local FAILED_PAGE_TEXT = "This page failed to load, see UE4SS.log"
-- ESlateVisibility
local VISIBLE, COLLAPSED = 0, 1
-- Overlay slot alignments: Left and Top are both 1, Fill is 0
local ALIGN_START, ALIGN_FILL = 1, 0

local isValid = ui.isValid
local addressOf = ui.addressOf

local panels = {}
local Panels = {}
Panels.__index = Panels

-- A router for the clicks of this panel: the same class the menus use, which owns the shared hooks (tile, tab widget)
-- and the click table. It never opens a menu, so only the fields below matter.
local ROUTER_MENU = { id = "panel", label = "cauldron panel", paging = false }

local function paramValue(param)
  local ok, value = pcall(function()
    return param:get()
  end)
  return ok and value or param
end

local function template(path)
  local ok, object = pcall(StaticFindObject, path)
  if ok and isValid(object) then
    return object
  end
end

local function classNameOf(object)
  local ok, name = pcall(function()
    return object:GetClass():GetFName():ToString()
  end)
  return ok and name or nil
end

local function contextActor(panel)
  local ok, actor = pcall(function()
    return panel.ContextActor
  end)
  if ok and isValid(actor) then
    return actor
  end
end

local function textOf(widget)
  local ok, text = pcall(function()
    return widget:GetText():ToString()
  end)
  return ok and text or nil
end

-- options: { registry = registry object, log = function(text) }
function panels.new(options)
  local self = setmetatable({}, Panels)
  self.registry = options.registry
  self.log = options.log
  self.router = tabs.new({ registry = options.registry, log = options.log, menu = ROUTER_MENU })
  self.gate = plan.newGate(options.log) -- refuses tab:refresh() while a page is being built
  self.state = nil -- the current panel (see stateFor)
  self.installed = false
  self.gaveUp = {} -- hook path -> true when its retries ran out
  self.stopPolling = nil
  self.noted = {} -- problems already logged, so each is said once
  self.openCounter = 0
  return self
end

function Panels:note(key, text)
  if not self.noted[key] then
    self.noted[key] = true
    self.log(text)
  end
end

-- Drops every page, click and loop of the panel being replaced. Nothing is called on the old widgets.
function Panels:forget()
  self:stopPollingNow()
  local state = self.state
  if state then
    state.active = false
    if state.session then
      state.session.alive = false
    end
  end
  self.router.clicks:reset()
  self.router.state = nil
  self.state = nil
end

-- Only one panel state is kept: the current panel. A different (new) panel replaces it.
function Panels:stateFor(panel)
  local address = addressOf(panel)
  local state = self.state
  if state and state.address == address and isValid(state.panel) then
    return state
  end
  self:forget()
  self.state = { panel = panel, address = address, built = false, active = false, records = {} }
  return self.state
end

-- ---------------------------------------------------------------------------------------------------------------
-- Hooks

function Panels:entries(only)
  local all = {
    {
      path = OPEN_HOOK,
      effect = "Mods cannot add side tabs to the cauldron panel.",
      fn = function(context)
        self:guarded("open", function()
          self:onOpen(paramValue(context))
        end)
      end,
    },
    {
      path = CLOSE_HOOK,
      effect = "Side tabs of the cauldron panel are not reset when it closes.",
      fn = function(context)
        self:guarded("close", function()
          self:onClose(paramValue(context))
        end)
      end,
    },
    {
      path = BUTTON_CLICK_HOOK,
      effect = "Buttons on the pages of the cauldron panel will not react to clicks.",
      fn = function(context)
        self.router:routeClick(context)
      end,
    },
  }
  local list = {}
  for _, entry in ipairs(all) do
    if only == nil or only[entry.path] then
      local path = entry.path
      entry.onGiveUp = function()
        self.gaveUp[path] = true
      end
      list[#list + 1] = entry
    end
  end
  return list
end

function Panels:guarded(what, fn)
  local ok, problem = pcall(fn)
  if not ok then
    self.log(string.format("could not update the cauldron panel on %s: %s", what, tostring(problem)))
  end
end

-- Registers the hooks (the panel class may not be loaded yet: hooks.lua retries) and the reset on world changes.
-- Called when the first panel tab is registered, so a game with no such mod is not touched.
function Panels:install()
  if self.installed then
    return
  end
  self.installed = true
  hooks.install(self:entries(), self.log)
  if type(RegisterInitGameStatePostHook) == "function" then
    local ok, problem = pcall(RegisterInitGameStatePostHook, function()
      self:guarded("a world change", function()
        self:worldChanged()
      end)
    end)
    if not ok then
      self.log(
        "could not watch for world changes, the cauldron panel tabs may stay on a dead panel: " .. tostring(problem)
      )
    end
  end
end

-- A world was loaded or left: nothing of the old panel may be touched again. Hooks that ran out of retries get
-- another round, because the class may load with the new world.
function Panels:worldChanged()
  self:forget()
  local retry = {}
  local any = false
  for path in pairs(self.gaveUp) do
    retry[path] = true
    any = true
  end
  if any then
    self.gaveUp = {}
    hooks.install(self:entries(retry), self.log)
  end
end

function Panels:cleanup()
  self:stopPollingNow()
  if self.state then
    self.state.active = false
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Building the panel (once per panel instance)

-- The Z panel's templates for one side tab, or nil and the reason. Loads the Z panel's class first if they are
-- missing, then looks again.
function Panels:templates()
  local function read()
    local found = {
      size = template(Z_TREE .. "SizeBox_71"),
      border = template(Z_TREE .. "Border_110"),
      text = template(Z_TREE .. "CommonTextBlock_122"),
      scale = template(Z_TREE .. "ScaleBox_1"),
    }
    if found.size and found.border and found.text and found.scale then
      return found
    end
  end
  local found = read()
  if not found then
    ui.findClass(Z_CLASS, self.log)
    found = read()
  end
  if found then
    return found
  end
  return nil, "the Z panel's tab templates were not found"
end

-- One side tab like the Z panel's: SizeBox > Border (the template's art and padding) > Overlay [ScaleBox >
-- CommonTextBlock, the game's tab widget made invisible on top to take the click]. The fixed width makes the
-- ScaleBox (stretch to fit, Fill alignment) shrink a long title.
function Panels:makeTab(state, title, templates, tabClass)
  local tree = state.tree
  local size = ui.construct(ui.CLASS.sizeBox, tree)
  size:SetWidthOverride(templates.size.WidthOverride)
  if templates.size.bOverride_HeightOverride then
    size:SetHeightOverride(templates.size.HeightOverride)
  end
  local border = ui.construct(BORDER_CLASS, tree)
  border.Background = templates.border.Background
  border:SetPadding(templates.border.Padding)
  local overlay = ui.construct(ui.CLASS.overlay, tree)
  local scale = ui.construct(ui.CLASS.scale, tree)
  scale:SetStretch(templates.scale.Stretch)
  scale:SetUserSpecifiedScale(templates.scale.UserSpecifiedScale)
  local label = ui.construct(COMMON_TEXT_CLASS, tree)
  local okStyle = pcall(function()
    label:SetStyle(templates.text.Style)
  end)
  if not okStyle then
    self:note("tab style", "could not copy the Z panel's tab text style: the side tab titles use the default style")
  end
  label:SetText(FText(title))
  scale:AddChild(label)
  local inner = overlay:AddChildToOverlay(scale)
  inner:SetHorizontalAlignment(ALIGN_FILL)
  inner:SetVerticalAlignment(ALIGN_FILL)
  local library = StaticFindObject(ui.CLASS.library)
  local click = library:Create(state.panel, tabClass, ui.playerController())
  if not isValid(click) then
    error("the game did not create a tab widget")
  end
  click.Title = FText("")
  click.Txt_Title:SetText(FText(""))
  click.Txt_Title_Highlight:SetText(FText(""))
  click:SetRenderOpacity(0.0)
  local fill = overlay:AddChildToOverlay(click)
  fill:SetHorizontalAlignment(ALIGN_FILL)
  fill:SetVerticalAlignment(ALIGN_FILL)
  border:SetContent(overlay)
  size:AddChild(border)
  return { title = title, size = size, border = border, click = click }
end

-- Reads the parts of the panel we rely on, without changing anything. Returns nil and the reason when it is not as
-- expected (the game was patched), so nothing is touched.
local function readPanel(state)
  local panel = state.panel
  local ok, parts = pcall(function()
    local tree = panel.WidgetTree
    local root = tree.RootWidget
    local body = root:GetChildAt(1) -- SizeBox_42 holds the title, this SizeBox > Border > VerticalBox_128 the content
    local border = body:GetContent()
    local content = border:GetContent()
    return { tree = tree, root = root, body = body, border = border, content = content }
  end)
  if not ok or not isValid(parts.content) then
    return nil, "the panel's content was not found where this version expects it (" .. tostring(parts) .. ")"
  end
  if classNameOf(parts.content) ~= "VerticalBox" then
    return nil,
      "the panel's content is not the game's VerticalBox (found "
        .. tostring(classNameOf(parts.content))
        .. "), for example left over from before a mod restart: load the save again"
  end
  local okTitle, titleWidget = pcall(function()
    return panel.Txt_FacilityTitle
  end)
  if not okTitle or not isValid(titleWidget) then
    return nil, "the panel has no Txt_FacilityTitle"
  end
  parts.titleWidget = titleWidget
  return parts
end

-- Builds the structure once for this panel instance: returns true, or nil and a reason when nothing was changed. An
-- error raised after the panel was touched is not caught here: the caller marks the panel as failed.
function Panels:buildStructure(state)
  local templates, reason = self:templates()
  if not templates then
    return nil, reason
  end
  local tabClass = ui.findClass(ui.CLASS.tagSwitcher, self.log)
  if not tabClass then
    return nil, "the tab widget class of the game was not found"
  end
  local parts, readReason = readPanel(state)
  if not parts then
    return nil, readReason
  end
  local list = self.registry:panelTabs(PANEL_ID)
  local tree = parts.tree
  state.tree = tree

  -- Everything is created first, so a failure here leaves the panel as the game made it: it is a soft failure, said
  -- once, and the next open tries again.
  local okPrepare, prepared = pcall(function()
    local made = { self:makeTab(state, GAME_TAB, templates, tabClass) }
    for _, entry in ipairs(list) do
      made[#made + 1] = self:makeTab(state, entry.title, templates, tabClass)
    end
    local tabsBox = ui.construct(ui.CLASS.vbox, tree)
    for _, tab in ipairs(made) do
      tabsBox:AddChildToVerticalBox(tab.size)
    end
    local pageHolder = ui.construct(ui.CLASS.sizeBox, tree)
    pageHolder:SetHeightOverride(PAGE_HEIGHT)
    local pageRoot = ui.construct(ui.CLASS.vbox, tree)
    pageHolder:AddChild(pageRoot)
    pageHolder:SetVisibility(COLLAPSED)
    return {
      made = made,
      tabsBox = tabsBox,
      pageHolder = pageHolder,
      pageRoot = pageRoot,
      inner = ui.construct(ui.CLASS.overlay, tree),
      outer = ui.construct(ui.CLASS.overlay, tree),
    }
  end)
  if not okPrepare then
    return nil, "the side tabs could not be prepared (" .. tostring(prepared) .. "), the panel was not changed"
  end
  local made, tabsBox, pageHolder, pageRoot = prepared.made, prepared.tabsBox, prepared.pageHolder, prepared.pageRoot
  local inner, outer = prepared.inner, prepared.outer
  -- The visibility the game gave its content, restored when the Cauldron tab is shown again.
  local okVisibility, visibility = pcall(function()
    return parts.content:GetVisibility()
  end)
  state.contentVisibility = okVisibility and type(visibility) == "number" and visibility or VISIBLE

  -- Then the panel is changed: the content and our page share an Overlay in the Border, and the tabs sit in an
  -- Overlay with the panel's body, moved left by the tab width.
  parts.content:RemoveFromParent()
  inner:AddChildToOverlay(parts.content)
  inner:AddChildToOverlay(pageHolder)
  parts.border:SetContent(inner)
  parts.body:RemoveFromParent()
  outer:AddChildToOverlay(parts.body)
  local tabsSlot = outer:AddChildToOverlay(tabsBox)
  tabsSlot:SetHorizontalAlignment(ALIGN_START)
  tabsSlot:SetVerticalAlignment(ALIGN_START)
  parts.root:AddChildToVerticalBox(outer)
  tabsBox:SetRenderTranslation({ X = -(templates.size.WidthOverride + 0.0), Y = TAB_OFFSET_Y })

  state.templates = templates
  state.content = parts.content
  state.border = parts.border
  state.body = parts.body
  state.inner = inner
  state.outer = outer
  state.pageHolder = pageHolder
  state.pageRoot = pageRoot
  state.tabsBox = tabsBox
  state.titleWidget = parts.titleWidget
  state.tabs = made
  state.records = {}
  for index, entry in ipairs(list) do
    state.records[entry.key] = { entry = entry, tab = made[index + 1] }
  end
  for index, tab in ipairs(made) do
    local record = index > 1 and state.records[list[index - 1].key] or nil
    self.router.clicks:register(addressOf(tab.click), {
      owner = "af-modloader-api",
      alive = function()
        return isValid(tab.click)
      end,
      fn = function()
        self:onTabClick(state, record)
      end,
    })
  end
  self.router:ensureSwitcherHook(tabClass)
  state.built = true
  return true
end

-- True while the structure we made is still in the panel: the content in our overlay inside the border, the body in
-- ours. If the game rebuilt any of it, the tabs are not used any more for this panel.
local function intact(state, log)
  local ok, same = pcall(function()
    return isValid(state.outer)
      and isValid(state.tabsBox)
      and isValid(state.pageRoot)
      and addressOf(state.border:GetContent()) == addressOf(state.inner)
  end)
  if not (ok and same == true) then
    return false
  end
  -- GetParent is not verified in game: if it raises, that check is skipped (said once), only a mismatch counts.
  local okParent, parent = pcall(function()
    return state.body:GetParent()
  end)
  if not okParent then
    if not state.parentNoted then
      state.parentNoted = true
      log("could not check where the cauldron panel's body is (unverified GetParent): the check is skipped")
    end
    return true
  end
  return addressOf(parent) == addressOf(state.outer)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Showing and hiding

-- The tab look: the same art for all, the selected one at full brightness.
local function paintTabs(state, title)
  for _, tab in ipairs(state.tabs) do
    pcall(function()
      tab.border:SetBrush(state.templates.border.Background)
      tab.border:SetPadding(state.templates.border.Padding)
      tab.border:SetBrushColor(tab.title == title and SELECTED_TINT or UNSELECTED_TINT)
    end)
  end
end

-- Ends the page that is showing: its session is dead, its clicks are dropped, its widgets are removed.
function Panels:killPage(state)
  if state.session then
    state.session.alive = false
    self.router.clicks:dropSession(state.session)
    state.session = nil
  end
  state.showing = nil
  if isValid(state.pageRoot) then
    pcall(function()
      state.pageRoot:ClearChildren()
    end)
  end
end

-- Back to the Cauldron tab: the page is killed, the game's content and title are restored.
function Panels:showGame(state)
  self:stopPollingNow()
  self:killPage(state)
  if not state.built then
    return
  end
  pcall(function()
    state.content:SetVisibility(state.contentVisibility or VISIBLE)
  end)
  pcall(function()
    state.pageHolder:SetVisibility(COLLAPSED)
  end)
  if state.titleChanged then
    state.titleChanged = false
    -- Only if the widget still shows our tab's title: a reopen may already have given it the new cauldron's.
    local title = state.gameTitle
    if textOf(state.titleWidget) == state.modTitle then
      pcall(function()
        state.titleWidget:SetText(FText(title))
      end)
    end
  end
  paintTabs(state, GAME_TAB)
end

local function setTabsVisible(state, visible)
  pcall(function()
    state.tabsBox:SetVisibility(visible and VISIBLE or COLLAPSED)
  end)
end

local function isCurrent(state, openId, actorAddress)
  if not (state.active and state.openId == openId and isValid(state.panel)) then
    return false
  end
  local actor = contextActor(state.panel)
  return actor ~= nil and addressOf(actor) == actorAddress
end

-- The argument of build(page, info). Everything in it is read again on each build of the page.
function Panels:makeInfo(state)
  local openId, actorAddress = state.openId, state.actorAddress
  local component
  local okComponent, value = pcall(function()
    return state.panel.CauldronComp
  end)
  if okComponent and isValid(value) then
    component = value
  end
  return registry.readonly({
    actor = state.actor,
    kind = state.kind,
    component = component,
    showGame = function()
      if isCurrent(state, openId, actorAddress) then
        self:showGame(state)
      end
    end,
    isCurrent = function()
      return isCurrent(state, openId, actorAddress)
    end,
  }, "info")
end

-- Fills the page by running the mod's build function. A failing build leaves one line saying so.
function Panels:fill(state, record)
  self.gate:run(function()
    if state.session then
      state.session.alive = false
      self.router.clicks:dropSession(state.session)
    end
    pcall(function()
      state.pageRoot:ClearChildren()
    end)
    local router = self.router
    local owner = record.entry.owner
    local ctx = {
      panel = state.panel,
      tree = state.tree,
      root = state.pageRoot,
      owner = owner,
      log = self.log,
      clicks = router.clicks,
      textColor = PAGE_TEXT_COLOR,
      onTileCreated = function(class)
        router:ensureTileHook(class)
      end,
      onMarkCreated = function(class)
        router:ensureSwitcherHook(class)
      end,
    }
    local page, session = ui.newPage(ctx)
    state.session = session
    local ok, problem = xpcall(record.entry.build, debug.traceback, page, self:makeInfo(state))
    if not ok then
      self.log(
        string.format('mod %s: the page of tab "%s" failed to build: %s', owner, record.entry.title, tostring(problem))
      )
      session.alive = false
      router.clicks:dropSession(session)
      pcall(function()
        state.pageRoot:ClearChildren()
      end)
      local failed, failedSession = ui.newPage(ctx)
      failed:text(FAILED_PAGE_TEXT)
      if state.session == session then
        state.session = failedSession
      end
    end
  end)
end

function Panels:showTab(state, record)
  self:stopPollingNow()
  if not state.titleChanged then
    -- Read when the player leaves the Cauldron tab: by then the game has set its title for this cauldron.
    local current = textOf(state.titleWidget)
    if current ~= nil then
      state.gameTitle = current
      state.titleChanged = true
    end
  end
  state.showing = record
  pcall(function()
    state.content:SetVisibility(COLLAPSED)
  end)
  pcall(function()
    state.pageHolder:SetVisibility(VISIBLE)
  end)
  if state.titleChanged then
    pcall(function()
      state.modTitle = record.entry.title
      state.titleWidget:SetText(FText(record.entry.title))
    end)
  end
  paintTabs(state, record.entry.title)
  self:fill(state, record)
  self:startPolling()
end

-- A click on one of the side tabs. record is nil for the game's own tab.
function Panels:onTabClick(state, record)
  if self.state ~= state or not state.active or not isValid(state.panel) then
    return
  end
  if record == nil then
    if state.showing ~= nil then
      self:showGame(state)
    end
  elseif state.showing ~= record then
    local ok, problem = pcall(function()
      self:showTab(state, record)
    end)
    if not ok then
      self.log(
        string.format('could not show the tab "%s" of the cauldron panel: %s', record.entry.title, tostring(problem))
      )
      self:showGame(state)
    end
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Open and close

function Panels:deactivate(state)
  self:stopPollingNow()
  state.active = false
  if self.router.state == state then
    self.router.state = nil
  end
  if isValid(state.panel) then
    self:showGame(state)
  else
    if state.session then
      state.session.alive = false
      self.router.clicks:dropSession(state.session)
      state.session = nil
    end
    state.showing = nil
  end
end

-- PostSetContextActor: the panel was opened for a cauldron (the hook is known to fire on every open).
-- The panel is only read and reset here. The first time for a panel instance the structure is built a moment later,
-- out of the game's callback (completeOpen): rebuilding the panel inside it is not safe.
function Panels:onOpen(panel)
  self.registry:seal()
  if #self.registry:panelTabs(PANEL_ID) == 0 or not isValid(panel) then
    return
  end
  local state = self:stateFor(panel)
  local actor = contextActor(panel)
  local actorClass = actor and classNameOf(actor) or nil
  local kind = actorClass and KINDS[actorClass] or nil
  state.openId = nil
  if not kind then
    if state.built then
      self:deactivate(state)
      setTabsVisible(state, false)
    end
    self:note(
      "class " .. tostring(actorClass),
      string.format(
        "the cauldron panel opened for %s, which is not a known cauldron: mod tabs are not shown for it",
        tostring(actorClass)
      )
    )
    return
  end
  if state.failed then
    return
  end
  if state.built and not intact(state, self.log) then
    state.failed = true
    self.log(
      "the game changed the cauldron panel after the side tabs were added: they are off until the save is loaded again"
    )
    return
  end
  self.openCounter = self.openCounter + 1
  local openId = self.openCounter
  state.openId = openId
  state.actor = actor
  state.actorAddress = addressOf(actor)
  state.kind = kind
  state.active = false
  if self.router.state == state then
    self.router.state = nil
  end
  if state.built then
    self:activate(state)
  else
    ExecuteInGameThread(function()
      self:guarded("open", function()
        self:completeOpen(state, openId)
      end)
    end)
  end
end

-- The deferred part of the first open of a panel instance. Does nothing when the panel was closed, replaced or
-- opened again in the meantime.
function Panels:completeOpen(state, openId)
  if self.state ~= state or state.openId ~= openId or state.built or state.failed or not isValid(state.panel) then
    return
  end
  local okBuild, built, reason = pcall(self.buildStructure, self, state)
  if not okBuild then
    state.failed = true
    self.log(
      "could not add the side tabs to the cauldron panel, it may look odd until the save is loaded again: "
        .. tostring(built)
    )
    return
  end
  if not built then
    self:note("structure " .. tostring(reason), "no side tabs on the cauldron panel: " .. tostring(reason))
    return
  end
  self.log(
    string.format(
      "cauldron panel: added %d side tab(s) for mods (%s cauldron, %d slot(s) expected)",
      #state.tabs - 1,
      state.kind,
      state.kind == "normal" and 3 or 2
    )
  )
  self:activate(state)
end

function Panels:activate(state)
  self:showGame(state)
  setTabsVisible(state, true)
  state.active = true
  self.router.state = state
end

-- BP_OnDeactivated: the panel closed. Nothing may stay of the page, and the loop stops.
function Panels:onClose(panel)
  local state = self.state
  if state and addressOf(panel) == state.address then
    state.openId = nil -- a build waiting to run for this open is cancelled
    if state.built then
      self:deactivate(state)
    end
  end
end

-- tab:refresh(): rebuilds the page now if this tab is showing. Called while a page is being built, it is refused
-- with a log line (see tabs_plan.lua newGate).
function Panels:refresh(entry)
  self.gate:request(entry, function()
    local state = self.state
    local record = state and state.records[entry.key]
    if record and state.active and state.showing == record and isValid(state.panel) then
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

-- ---------------------------------------------------------------------------------------------------------------
-- Input polling (docs/api.md: onChange), only while a mod page shows

function Panels:poll(mine)
  local state = self.state
  if state ~= mine or not state.active then
    self:stopPollingNow()
    return
  end
  if not isValid(state.panel) then
    self:deactivate(state)
    return
  end
  local session = state.session
  if not (session and session.alive) then
    return
  end
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

function Panels:startPolling()
  if self.stopPolling then
    return
  end
  local mine = self.state
  local stop, how = loop.start(POLL_MS, function()
    self:poll(mine)
  end, self.log)
  if stop then
    self.stopPolling = stop
    self:note("loop", "cauldron panel input onChange is polled with " .. how)
  else
    self:note(
      "loop failed",
      "input onChange will not work in the cauldron panel: no timed loop could be started (" .. tostring(how) .. ")"
    )
  end
end

function Panels:stopPollingNow()
  if self.stopPolling then
    self.stopPolling()
    self.stopPolling = nil
  end
end

return panels
