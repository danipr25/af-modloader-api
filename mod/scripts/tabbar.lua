-- The TAB menu's tab bar when the tabs do not all fit: shows a window of the tabs and two arrows to move it.
-- Game-facing, tested in game; the decisions are in tabbar_plan.lua (tested without the game). The mechanism comes from
-- docs/tab-menu.md ("Paging the tab bar", verified in game 1.1.5024, 2026-10-22): hide tab buttons with
-- SetVisibility(Collapsed) (TitleList is not touched, so every visible tab opens its own page), narrow the bar with
-- the slot padding, and put two arrows made from the game's own tab widget in the overlay that holds the bar.
-- Only the TAB menu's bar is touched. Every game call is in pcall: a failure logs one line for that panel, turns
-- paging off for it and shows every tab again, so the game's own tabs are never left hidden.
local plan = require("tabbar_plan")
local ui = require("ui")

local TAB_CLASS = "/Game/Blueprints/WBP/Utility/WBP_TagSwitcher.WBP_TagSwitcher_C"
local ARROW_TEXTURE = "/Game/Arts/UI/Interaction/T_UI_RightArrow.T_UI_RightArrow"
local CLICK_HOOK = TAB_CLASS .. ":OnMouseButtonDown"
local OWNER = "af-modloader-api"
-- ESlateVisibility, and the overlay slot alignments (verified in the tab bar probe, 2026-10-22).
local VISIBLE, COLLAPSED, HIT_TEST_INVISIBLE = 0, 1, 3
local H_LEFT, H_CENTER, H_RIGHT, V_TOP, V_CENTER = 1, 2, 3, 1, 2
local ARROW_WIDTH = 64
local ARROW_SIZE = 36
local GAP = 4
local GOLD = { R = 1.0, G = 0.75, B = 0.2, A = 1.0 }
local GREY = { R = 0.45, G = 0.42, B = 0.38, A = 1.0 }

local isValid = ui.isValid
local addressOf = ui.addressOf
local tabbar = {}
local Bar = {}
Bar.__index = Bar

local function className(object)
  return object:GetClass():GetFName():ToString()
end

-- options: { log = function(text), clicks = the click router, route = function(context) for the tab click hook }
function tabbar.new(options)
  local self = setmetatable({}, Bar)
  self.log = options.log
  self.clicks = options.clicks
  self.route = options.route
  self.widths = {} -- title -> measured width (a title keeps its width; 0 is never stored)
  self.hook = "none" -- "none", "scheduled" or "registered"
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
-- be an Overlay whose child 1 is the page box (a SizeBox), found by position because the box is not a variable.
local function readGeometry(group)
  local overlay = group:GetParent()
  if not isValid(overlay) or className(overlay) ~= "Overlay" then
    error("the tab bar is not inside an Overlay", 0)
  end
  local box = overlay:GetChildAt(1)
  if not isValid(box) or className(box) ~= "SizeBox" then
    error("the page box next to the tab bar was not found", 0)
  end
  local width = box.bOverride_WidthOverride and box.WidthOverride or box:GetDesiredSize().X
  local padding = group.Slot.Padding
  local original = { Left = padding.Left, Top = padding.Top, Right = padding.Right, Bottom = padding.Bottom }
  if type(width) ~= "number" or width <= 0 or type(original.Left) ~= "number" then
    error("the width of the page box could not be read", 0)
  end
  return {
    overlay = overlay,
    padding = original,
    available = width - original.Left,
    translationY = group.RenderTransform.Translation.Y + 0.0,
  }
end

-- The arrow texture: already loaded (verified right after loading a save), else LoadAsset once. Logged once.
function Bar:findTexture()
  local texture = StaticFindObject(ARROW_TEXTURE)
  if not isValid(texture) and type(LoadAsset) == "function" then
    pcall(LoadAsset, ARROW_TEXTURE)
    texture = StaticFindObject(ARROW_TEXTURE)
    if not self.loggedTexture then
      self.loggedTexture = true
      self.log(
        isValid(texture) and ("game texture " .. ARROW_TEXTURE .. ": loaded with LoadAsset")
          or ("game texture " .. ARROW_TEXTURE .. " is not available: the tab bar cannot show its arrows")
      )
    end
  end
  if not isValid(texture) then
    error("the arrow texture is not available", 0)
  end
  return texture
end

-- One arrow: the game's tab widget with no title and a fixed width, the arrow image on top (gold, mirrored for
-- "previous", not hit-testable so the click lands on the tab), all in a small Overlay inside the bar's overlay.
local function makeArrow(state, geometry, side, texture)
  local library = StaticFindObject(ui.CLASS.library)
  local tabClass = StaticFindObject(TAB_CLASS)
  if not isValid(tabClass) then
    error("the tab class is not loaded", 0)
  end
  local controller = FindFirstOf("PlayerController")
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
  local texture = self:findTexture()
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
  self:ensureClickHook(addressOf(StaticFindObject(TAB_CLASS)))
end

-- Registers the arrows' click hook once the tab class is known to be loaded. Called whenever arrows are made: cheap
-- once registered, a failed registration is tried again the next time. Deferred to the game thread. If the class was
-- loaded again since (a different object), the hook is registered again: a hook belongs to the class object.
function Bar:ensureClickHook(address)
  if self.hook == "scheduled" then
    return
  end
  if self.hook ~= "none" then
    if address == nil or address == self.hookClass then
      return
    end
    self.log("the game loaded the tab class again: hooking tab bar arrow clicks again")
  end
  self.hook = "scheduled"
  self.hookClass = address
  ExecuteInGameThread(function()
    local ok, problem = pcall(RegisterHook, CLICK_HOOK, function(context)
      self.route(context)
    end)
    if ok then
      self.hook = "registered"
      self.log("tab bar arrow clicks are on: hooked " .. CLICK_HOOK)
    else
      self.hook = "none"
      self.hookClass = nil
      if not self.loggedHookFailure then
        self.loggedHookFailure = true
        self.log(
          "could not hook "
            .. CLICK_HOOK
            .. " ("
            .. tostring(problem)
            .. "). The arrows of the tab bar will not react to clicks until it succeeds; it is tried again the next "
            .. "time the arrows are made."
        )
      end
    end
  end)
end

local function setVisibility(widgets, visibility)
  for _, widget in ipairs(widgets) do
    pcall(function()
      widget:SetVisibility(visibility)
    end)
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
      arrow.container:SetVisibility(COLLAPSED)
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
      Right = ARROW_WIDTH + GAP + 0.0,
      Bottom = padding.Bottom,
    })
    for side, arrow in pairs(rec.arrows) do
      local canMove = side == "next" and window.canNext or side == "previous" and window.canPrev
      arrow.container:SetVisibility(VISIBLE)
      arrow.image:SetColorAndOpacity(canMove and GOLD or GREY)
    end
  else
    group.Slot:SetPadding(padding)
    for _, arrow in pairs(rec.arrows or {}) do
      arrow.container:SetVisibility(COLLAPSED)
    end
  end
end

-- Measures, plans and shows the window. Raises on any problem (update handles it).
function Bar:apply(state, rec, group)
  rec.group = group
  if not rec.geometry then
    rec.geometry = readGeometry(group)
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

-- Called when the TAB menu opens, after Tabs:ensure ('healthy' is whether ensure found the panel as expected), and
-- after an arrow click. An unhealthy menu gets its bar back as the game made it.
function Bar:update(state, group, healthy)
  local rec = state.bar
  if not rec then
    rec = { first = 1, logged = {} }
    state.bar = rec
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
