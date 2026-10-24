-- The TAB menu's tab bar when the tabs do not all fit: shows a window of the tabs and two arrows to move it.
-- Game-facing, tested in game; the decisions are in tabbar_plan.lua (tested without the game). The mechanism comes from
-- docs/tab-menu.md ("Paging the tab bar", verified in game 1.1.5024, 2026-10-22): hide tab buttons with
-- SetVisibility(Collapsed) (TitleList is not touched, so every visible tab opens its own page), narrow the bar with
-- the slot padding, and put two arrows made from the game's own tab widget in the overlay that holds the bar.
-- Only the TAB menu's bar is touched. Every game call is in pcall: a failure logs one line for that panel, turns
-- paging off for it and shows every tab again, so the game's own tabs are never left hidden.
local plan = require("tabbar_plan")
local ui = require("ui")

local TAB_CLASS = ui.CLASS.tagSwitcher
local OWNER = "af-modloader-api"
-- ESlateVisibility, and the overlay slot alignments (verified in the tab bar probe, 2026-10-22).
local VISIBLE, COLLAPSED, HIT_TEST_INVISIBLE = 0, 1, 3
local H_LEFT, H_CENTER, H_RIGHT, V_TOP, V_CENTER = 1, 2, 3, 1, 2
local ARROW_WIDTH = 64
local ARROW_SIZE = 36
local GAP = 4
local GOLD, GREY = ui.GOLD, ui.GREY

local isValid = ui.isValid
local addressOf = ui.addressOf
local tabbar = {}
local Bar = {}
Bar.__index = Bar

local function className(object)
  return object:GetClass():GetFName():ToString()
end

-- options: { log = function(text), clicks = the click router,
--            ensureHook = function(class) makes sure the router hears clicks on the tab widget class (tabs.lua owns
--            that one hook, the arrows and the marks of row:mark share it) }
function tabbar.new(options)
  local self = setmetatable({}, Bar)
  self.log = options.log
  self.clicks = options.clicks
  self.ensureHook = options.ensureHook
  self.widths = {} -- title -> measured width (a title keeps its width; 0 is never stored)
  return self
end

-- One log line per kind of problem per panel.
function Bar:note(rec, kind, text)
  if not rec.logged[kind] then
    rec.logged[kind] = true
    self.log(text)
  end
end

-- The tab buttons in order (EntryList holds objects wrapped by UE4SS).
local function entriesOf(group)
  local list = {}
  for index = 1, #group.EntryList do
    local element = group.EntryList[index]
    local okGet, object = pcall(function()
      return element:get()
    end)
    list[#list + 1] = (okGet and isValid(object)) and object or element
  end
  return list
end

local function titlesOf(group)
  local titles = {}
  for index = 1, #group.TitleList do
    titles[index] = group.TitleList[index]:ToString()
  end
  return titles
end

-- Where the bar lives and how much room it has, read once per panel before anything is changed: the bar's parent must
-- be an Overlay with exactly one SizeBox child, the page box, found by class because it is not a variable and its
-- position changes when the arrows are put under it.
local function readGeometry(group, knownPadding)
  local overlay = group:GetParent()
  if not isValid(overlay) or className(overlay) ~= "Overlay" then
    error("the tab bar is not inside an Overlay", 0)
  end
  local box, boxes = nil, 0
  for index = 0, overlay:GetChildrenCount() - 1 do
    local child = overlay:GetChildAt(index)
    if isValid(child) and className(child) == "SizeBox" then
      box = child
      boxes = boxes + 1
    end
  end
  if boxes ~= 1 then
    error(string.format("expected one page box next to the tab bar, found %d", boxes), 0)
  end
  -- bOverride_WidthOverride is a bitfield: set when true or 1.
  local flag = box.bOverride_WidthOverride
  local width = (flag == true or flag == 1) and box.WidthOverride or box:GetDesiredSize().X
  local padding = group.Slot.Padding
  local original = knownPadding
    or { Left = padding.Left, Top = padding.Top, Right = padding.Right, Bottom = padding.Bottom }
  if type(width) ~= "number" or width <= 0 or type(original.Left) ~= "number" then
    error("the width of the page box could not be read", 0)
  end
  return {
    overlay = overlay,
    box = box,
    padding = original,
    available = width - original.Left - original.Right,
    translationY = group.RenderTransform.Translation.Y + 0.0,
  }
end

-- One arrow: the game's tab widget with no title and a fixed width, the arrow image on top (gold, mirrored for
-- "previous", not hit-testable so the click lands on the tab), all in a small Overlay inside the bar's overlay.
local function makeArrow(state, geometry, side, texture)
  local library = StaticFindObject(ui.CLASS.library)
  local tabClass = StaticFindObject(TAB_CLASS)
  if not isValid(tabClass) then
    error("the tab class is not loaded", 0)
  end
  local controller = ui.playerController()
  local container = ui.construct("/Script/UMG.Overlay", state.tree)
  local tab = library:Create(state.panel, tabClass, controller)
  container:AddChildToOverlay(tab)
  tab.Title = FText("")
  tab.Txt_Title:SetText(FText(""))
  tab.Txt_Title_Highlight:SetText(FText(""))
  local root = tab.WidgetTree.RootWidget
  root:SetMinDesiredWidth(ARROW_WIDTH + 0.0)
  root:SetMaxDesiredWidth(ARROW_WIDTH + 0.0)
  local image = ui.construct("/Script/UMG.Image", state.tree)
  image:SetBrushFromTexture(texture, false)
  image:SetDesiredSizeOverride({ X = ARROW_SIZE + 0.0, Y = ARROW_SIZE + 0.0 })
  image:SetColorAndOpacity(GOLD)
  image:SetVisibility(HIT_TEST_INVISIBLE)
  if side == "previous" then
    image:SetRenderScale({ X = -1.0, Y = 1.0 })
  end
  local inner = container:AddChildToOverlay(image)
  inner:SetHorizontalAlignment(H_CENTER)
  inner:SetVerticalAlignment(V_CENTER)
  local slot = geometry.overlay:AddChildToOverlay(container)
  slot:SetHorizontalAlignment(side == "next" and H_RIGHT or H_LEFT)
  slot:SetVerticalAlignment(V_TOP)
  if side == "previous" then
    slot:SetPadding({ Left = geometry.padding.Left, Top = 0.0, Right = 0.0, Bottom = 0.0 })
  end
  container:SetRenderTranslation({ X = 0.0, Y = geometry.translationY })
  return { container = container, tab = tab, image = image, address = addressOf(tab) }
end

local function removeArrow(arrow)
  pcall(function()
    arrow.container:RemoveFromParent()
  end)
end

-- Creates both arrows once per panel and registers them in the click router. A failure takes back what was made.
function Bar:ensureArrows(state, rec)
  if rec.arrows then
    return
  end
  local texture = ui.findTexture(ui.ARROW_TEXTURE, self.log)
  if texture == nil then
    error("the arrow texture is not available", 0)
  end
  local made = {}
  local ok, problem = pcall(function()
    made.previous = makeArrow(state, rec.geometry, "previous", texture)
    made.next = makeArrow(state, rec.geometry, "next", texture)
  end)
  if not ok then
    for _, arrow in pairs(made) do
      removeArrow(arrow)
    end
    error(problem, 0)
  end
  rec.arrows = made
  self:moveBoxLast(rec)
  for side, arrow in pairs(made) do
    self.clicks:register(arrow.address, {
      owner = OWNER,
      alive = function()
        return isValid(arrow.tab)
      end,
      fn = function()
        self:step(state, side)
      end,
    })
  end
  self.ensureHook(StaticFindObject(TAB_CLASS))
end

-- Puts the page box last in the overlay so it is drawn over the arrows, as it is over the real tabs: the arrows were
-- added after it and would cover its frame. Its padding and alignments are copied to the new slot. Once per panel,
-- when the arrows are first made (RemoveChild, AddChildToOverlay of the box: verified in game 1.1.5024). On a failure
-- the order stays as it is: the arrows still work, they are only drawn over the frame.
function Bar:moveBoxLast(rec)
  local geometry = rec.geometry
  local box = geometry.box
  local kept, horizontal, vertical
  local function restoreSlot(slot)
    slot:SetPadding(kept)
    slot:SetHorizontalAlignment(horizontal)
    slot:SetVerticalAlignment(vertical)
  end
  local ok, problem = pcall(function()
    local slot = box.Slot
    local padding = slot.Padding
    kept = { Left = padding.Left, Top = padding.Top, Right = padding.Right, Bottom = padding.Bottom }
    horizontal, vertical = slot.HorizontalAlignment, slot.VerticalAlignment
    geometry.overlay:RemoveChild(box)
    restoreSlot(geometry.overlay:AddChildToOverlay(box))
  end)
  if not ok then
    -- The pages must never disappear: if the box left the overlay, put it back; if it is back with a new slot, give
    -- that slot the old padding and alignments.
    local back = false
    pcall(function()
      if not isValid(box:GetParent()) then
        geometry.overlay:AddChildToOverlay(box)
      end
      back = isValid(box:GetParent())
      if kept then
        restoreSlot(box.Slot)
      end
    end)
    if back then
      self:note(
        rec,
        "order",
        "could not put the page box over the tab bar arrows ("
          .. tostring(problem)
          .. "): they are drawn over its frame"
      )
    else
      self:note(
        rec,
        "order",
        "could not put the pages of the TAB menu back after moving them ("
          .. tostring(problem)
          .. "). Load the save again to get them back."
      )
    end
  end
end

local function setVisibility(widgets, visibility)
  for _, widget in ipairs(widgets) do
    pcall(function()
      widget:SetVisibility(visibility)
    end)
  end
end

-- The first time this Lua state sees a panel, undoes what an earlier Lua state may have left in it (the widgets survive
-- a UE4SS mods restart, the Lua state does not): old arrows are removed, the padding they needed is taken off (the
-- result is the bar's original padding) and every tab is shown. Runs before anything else reads the padding.
function Bar:cleanLeftovers(rec, group)
  local okShow, showProblem = pcall(function()
    setVisibility(entriesOf(group), VISIBLE)
  end)
  if not okShow then
    self:note(rec, "leftoverShow", "could not show every tab of the TAB bar: " .. tostring(showProblem))
  end
  local ok, problem = pcall(function()
    local overlay = group:GetParent()
    if not isValid(overlay) or className(overlay) ~= "Overlay" then
      return
    end
    local found, shown = 0, 0
    for index = overlay:GetChildrenCount() - 1, 1, -1 do
      local child = overlay:GetChildAt(index)
      if isValid(child) and className(child) == "Overlay" then
        local inner = child:GetChildAt(0)
        if isValid(inner) and className(inner) == "WBP_TagSwitcher_C" then
          -- Collapsed arrows mean the old state had already given the bar its padding back.
          if child:GetVisibility() ~= COLLAPSED then
            shown = shown + 1
          end
          child:RemoveFromParent()
          found = found + 1
        end
      end
    end
    if shown > 0 then
      local padding = group.Slot.Padding
      rec.knownPadding = {
        Left = padding.Left - (ARROW_WIDTH + GAP),
        Top = padding.Top,
        Right = padding.Right - (ARROW_WIDTH + GAP),
        Bottom = padding.Bottom,
      }
      group.Slot:SetPadding(rec.knownPadding)
      self:note(
        rec,
        "leftover",
        string.format("removed %d tab bar arrow(s) left over from before a mods restart and showed every tab", found)
      )
    elseif found > 0 then
      self:note(
        rec,
        "leftover",
        string.format("removed %d hidden tab bar arrow(s) left over from before a mods restart", found)
      )
    end
  end)
  if not ok then
    self:note(rec, "leftover", "could not clean up the tab bar after a mods restart: " .. tostring(problem))
  end
end

-- Puts the bar back the way the game made it: every tab visible, the original padding, the arrows collapsed.
-- Only when something was changed.
function Bar:reset(rec, group)
  if not rec.touched then
    return
  end
  rec.touched = false
  rec.window = nil
  local ok, problem = pcall(function()
    setVisibility(entriesOf(group), VISIBLE)
    if rec.geometry then
      group.Slot:SetPadding(rec.geometry.padding)
    end
    for _, arrow in pairs(rec.arrows or {}) do
      if isValid(arrow.container) then
        arrow.container:SetVisibility(COLLAPSED)
      end
    end
  end)
  if not ok then
    self:note(rec, "reset", "could not put the tab bar back as the game made it: " .. tostring(problem))
  end
end

-- The width of every tab. Only tabs whose title has no width yet are made visible and measured (a collapsed tab
-- measures 0): one layout pass gives their widths in the same call. Unknown widths stay nil (the plan counts them
-- as the tab minimum).
function Bar:measure(group, entries, titles)
  local unknown = {}
  for index, title in ipairs(titles) do
    if self.widths[title] == nil then
      unknown[#unknown + 1] = index
    end
  end
  if #unknown > 0 then
    for _, index in ipairs(unknown) do
      entries[index]:SetVisibility(VISIBLE)
    end
    group:ForceLayoutPrepass()
    for _, index in ipairs(unknown) do
      local ok, width = pcall(function()
        return entries[index]:GetDesiredSize().X
      end)
      if ok and type(width) == "number" and width > 0 then
        self.widths[titles[index]] = width
      end
    end
  end
  local widths = {}
  for index, title in ipairs(titles) do
    widths[index] = self.widths[title]
  end
  return widths
end

local function describe(widths, count)
  local parts = {}
  for index = 1, count do
    parts[index] = widths[index] and string.format("%.0f", widths[index]) or "?"
  end
  return table.concat(parts, ", ")
end

-- Shows the window: tabs outside it collapsed, arrows and padding as the window needs.
local function show(rec, group, entries, window)
  rec.touched = true
  for index, entry in ipairs(entries) do
    entry:SetVisibility((index >= window.first and index <= window.last) and VISIBLE or COLLAPSED)
  end
  local padding = rec.geometry.padding
  if window.paged then
    group.Slot:SetPadding({
      Left = padding.Left + ARROW_WIDTH + GAP,
      Top = padding.Top,
      Right = padding.Right + ARROW_WIDTH + GAP,
      Bottom = padding.Bottom,
    })
    for side, arrow in pairs(rec.arrows) do
      local canMove = side == "next" and window.canNext or side == "previous" and window.canPrev
      if isValid(arrow.container) and isValid(arrow.image) then
        arrow.container:SetVisibility(VISIBLE)
        arrow.image:SetColorAndOpacity(canMove and GOLD or GREY)
      end
    end
  else
    group.Slot:SetPadding(padding)
    for _, arrow in pairs(rec.arrows or {}) do
      if isValid(arrow.container) then
        arrow.container:SetVisibility(COLLAPSED)
      end
    end
  end
end

-- Measures, plans and shows the window. Raises on any problem (update handles it).
function Bar:apply(state, rec, group)
  rec.group = group
  if not rec.geometry then
    rec.geometry = readGeometry(group, rec.knownPadding)
  end
  local entries, titles = entriesOf(group), titlesOf(group)
  if #entries ~= #titles then
    error(string.format("the tab bar has %d buttons but %d titles", #entries, #titles), 0)
  end
  local widths = self:measure(group, entries, titles)
  rec.options = {
    count = #titles,
    widths = widths,
    available = rec.geometry.available,
    arrow = ARROW_WIDTH,
    gap = GAP,
    first = rec.first,
  }
  local window = plan.window(rec.options)
  rec.first = window.first
  if window.paged then
    self:ensureArrows(state, rec)
    self:note(
      rec,
      "paging",
      string.format(
        "TAB bar paging is on: %d tabs (widths %s) do not fit in %.0f, showing tabs %d to %d",
        #titles,
        describe(widths, #titles),
        rec.geometry.available,
        window.first,
        window.last
      )
    )
  end
  if window.paged or rec.touched then
    show(rec, group, entries, window)
  end
  rec.window = window
end

-- Whether what a record remembers no longer matches the live panel: the bar sits in another overlay, or the page box
-- or an arrow is gone (the game rebuilt the panel under the same address, or a leftover Lua state's widgets died).
local function isStale(rec, group)
  local geometry = rec.geometry
  if not geometry then
    return false
  end
  local ok, stale = pcall(function()
    if addressOf(group:GetParent()) ~= addressOf(geometry.overlay) or not isValid(geometry.box) then
      return true
    end
    for _, arrow in pairs(rec.arrows or {}) do
      if not (isValid(arrow.container) and isValid(arrow.image) and isValid(arrow.tab)) then
        return true
      end
    end
    return false
  end)
  return not ok or stale
end

-- Called when the TAB menu opens, after Tabs:ensure ('healthy' is whether ensure found the panel as expected), and
-- after an arrow click. An unhealthy menu gets its bar back as the game made it.
function Bar:update(state, group, healthy)
  local rec = state.bar
  if rec and isStale(rec, group) then
    for _, arrow in pairs(rec.arrows or {}) do
      self.clicks:forget(arrow.address)
    end
    rec = nil -- start fresh, as for a new panel
  end
  if not rec then
    rec = { first = 1, logged = {} }
    state.bar = rec
    self:cleanLeftovers(rec, group)
  end
  if not healthy then
    self:reset(rec, group)
    return
  end
  if rec.off then
    return
  end
  local ok, problem = pcall(function()
    self:apply(state, rec, group)
  end)
  if not ok then
    rec.off = true
    self:note(
      rec,
      "failed",
      "the TAB bar will not page in this menu ("
        .. tostring(problem)
        .. "). All the tabs are shown; the last ones may run past the panel."
    )
    for _, arrow in pairs(rec.arrows or {}) do
      self.clicks:forget(arrow.address)
    end
    rec.touched = true -- the failure may have come after a change: make sure the reset runs
    self:reset(rec, group)
  end
end

-- A click on an arrow: moves the window by one view. An arrow that cannot move does nothing.
function Bar:step(state, side)
  local rec = state.bar
  if not rec or rec.off or not rec.window or not rec.window.paged or not isValid(rec.group) then
    return
  end
  local moved = plan.step(rec.options, side)
  if moved.first == rec.window.first then
    return
  end
  rec.first = moved.first
  self:update(state, rec.group, true)
end

return tabbar
