-- Contract of the layout widgets in ui.lua: page:columns, pane:clear and the spaces. The game is replaced by a small
-- fake that records what is built and which calls reach the slots, so this proves the checks, the numbers sent to
-- the game and the lifetime of panes. How they look in game is not tested here.
local lu = require("luaunit")
local clicks = require("clicks")
local ui = require("ui")

local GLOBALS = { "StaticFindObject", "StaticConstructObject", "FText", "FName", "FindFirstOf" }

-- A widget that records every call, every property write and every AddChild in one ordered list (fake.events), and
-- answers the few calls that return something. Properties the API reads a widget of (a button's border) give a
-- widget of their own.
local fake
local SUB_WIDGETS = { ContentBorder = true, Txt_BuildOptionType = true }
local function newWidget(class)
  local widget = { class = class, calls = {}, address = #fake.widgets + 1 }
  fake.widgets[#fake.widgets + 1] = widget
  return setmetatable(widget, {
    __newindex = function(self, name, value)
      fake.events[#fake.events + 1] = { kind = "write", widget = self, name = name, value = value }
      rawset(self, name, value)
    end,
    __index = function(self, name)
      if SUB_WIDGETS[name] then
        local child = newWidget(name)
        rawset(self, name, child)
        return child
      end
      return function(target, ...)
        target.calls[#target.calls + 1] = { name = name, args = { ... } }
        if name:find("^AddChild") then
          fake.events[#fake.events + 1] = { kind = "add", parent = target, child = (...) }
        end
        if name:find("^AddChildTo") then
          return newWidget("slot")
        elseif name == "IsValid" then
          return true
        elseif name == "GetAddress" then
          return self.address
        elseif name == "GetText" then
          return {
            ToString = function()
              return ""
            end,
          }
        end
      end
    end,
  })
end

local function callsOf(widget, name)
  local found = {}
  for _, call in ipairs(widget.calls) do
    if call.name == name then
      found[#found + 1] = call.args
    end
  end
  return found
end

local function ofClass(class)
  local found = {}
  for _, widget in ipairs(fake.widgets) do
    if widget.class == class then
      found[#found + 1] = widget
    end
  end
  return found
end

local function setupGame()
  fake = { widgets = {}, saved = {}, logs = {}, events = {}, missing = {} }
  for _, name in ipairs(GLOBALS) do
    fake.saved[name] = _G[name]
  end
  -- The game's style templates: they carry the values the API must copy. fake.missing[path] = true hides a path.
  fake.templates = {
    [ui.SCROLL_TEMPLATE] = { WidgetBarStyle = "bar style", ScrollbarThickness = 22.0 },
    [ui.SEARCH_TEMPLATE] = { WidgetStyle = "search style" },
  }
  _G.StaticFindObject = function(path)
    if fake.missing[path] then
      return nil
    end
    local object = fake.templates[path] or {}
    object.path = path
    object.IsValid = function()
      return true
    end
    object.Create = function(_, _, class)
      return newWidget(class.path == ui.CLASS.divider and "divider" or "tile")
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
  _G.FindFirstOf = function() end
end

local function restoreGame()
  for _, name in ipairs(GLOBALS) do
    _G[name] = fake.saved[name]
  end
end

-- A page on the fake game. Returns the page, its session and the click router.
local function newPage()
  local router = clicks.new(function(text)
    fake.logs[#fake.logs + 1] = text
  end)
  local root = newWidget("root")
  local page, session = ui.newPage({
    panel = newWidget("panel"),
    tree = newWidget("tree"),
    root = root,
    owner = "test-mod",
    log = function(text)
      fake.logs[#fake.logs + 1] = text
    end,
    clicks = router,
  })
  return page, session, router, root
end

-- Position of the first event that matches in fake.events (nil when none).
local function eventIndex(matches)
  for i, event in ipairs(fake.events) do
    if matches(event) then
      return i
    end
  end
end

local function writeOf(widget, name)
  return eventIndex(function(event)
    return event.kind == "write" and event.widget == widget and event.name == name
  end)
end

local function addOf(child)
  return eventIndex(function(event)
    return event.kind == "add" and event.child == child
  end)
end

local function logsWith(text)
  local found = 0
  for _, line in ipairs(fake.logs) do
    if line:find(text, 1, true) then
      found = found + 1
    end
  end
  return found
end

local function countClicks(router)
  local n = 0
  for _ in pairs(router.entries) do
    n = n + 1
  end
  return n
end

local function isFloats(...)
  for _, value in ipairs({ ... }) do
    if math.type(value) ~= "float" then
      return false
    end
  end
  return true
end

return {
  TestLayout = {
    setUp = setupGame,
    tearDown = restoreGame,

    testBadSizesAreRejectedAtTheModsCallBeforeAnythingIsBuilt = function()
      local page = newPage()
      local row = page:row()
      local list = page:list()
      local bad = { 0, -1, 401, math.huge, -math.huge, 0 / 0, "12", {}, true }
      for _, value in ipairs(bad) do
        for _, call in ipairs({
          function()
            page:space(value)
          end,
          function()
            row:space(value)
          end,
          function()
            list:row():space(value)
          end,
        }) do
          local ok, message = pcall(call)
          lu.assertFalse(ok)
          lu.assertStrContains(message, "test_ui_layout.lua") -- the error points at the mod's line
          lu.assertStrContains(message, "above 0 and up to 400")
        end
      end
      local ok = pcall(function()
        page:space()
      end)
      lu.assertFalse(ok)
      -- Only the list rows made by the loop above exist; no spacer was built for a bad size.
      lu.assertEquals(#ofClass(ui.CLASS.spacer), 0)
    end,

    testBadWidthsAreRejectedBeforeAnythingIsBuilt = function()
      local page = newPage()
      local built = #fake.widgets
      local bad = { {}, { 1 }, { 1, 0 }, { 1, -1 }, { 1, math.huge }, { 1, 0 / 0 }, { 1, "2" }, "1,2", 3, true }
      for _, widths in ipairs(bad) do
        local ok, message = pcall(function()
          page:columns(widths)
        end)
        lu.assertFalse(ok)
        lu.assertStrContains(message, "test_ui_layout.lua")
        lu.assertStrContains(message, "page:columns needs an array of 2 or more widths above 0")
      end
      lu.assertFalse(pcall(function()
        page:columns()
      end))
      lu.assertEquals(#fake.widgets, built)
    end,

    testSpacesReachTheGameAsFloats = function()
      local page = newPage()
      page:space(12)
      page:row():space(32)
      local spacers = ofClass(ui.CLASS.spacer)
      lu.assertEquals(#spacers, 2)
      local vertical = callsOf(spacers[1], "SetSize")[1][1]
      lu.assertEquals(vertical, { X = 0.0, Y = 12.0 })
      lu.assertTrue(isFloats(vertical.X, vertical.Y))
      local horizontal = callsOf(spacers[2], "SetSize")[1][1]
      lu.assertEquals(horizontal, { X = 32.0, Y = 0.0 })
      lu.assertTrue(isFloats(horizontal.X, horizontal.Y))
    end,

    testColumnsMakeOnePaneEachWithFloatWeightsAndOneGap = function()
      local page = newPage()
      local panes = page:columns({ 1, 2, 1 })
      lu.assertEquals(#panes, 3)
      local slots = ofClass("slot")
      local sizes, paddings = {}, {}
      for _, slot in ipairs(slots) do
        for _, args in ipairs(callsOf(slot, "SetSize")) do
          sizes[#sizes + 1] = args[1]
        end
        for _, args in ipairs(callsOf(slot, "SetPadding")) do
          paddings[#paddings + 1] = args[1]
        end
      end
      -- The first slot is the columns box on the page (it fills the page); the three after it are the panes.
      lu.assertEquals(#sizes, 4)
      for i = 2, 4 do
        lu.assertTrue(isFloats(sizes[i].Value))
        lu.assertEquals(sizes[i].SizeRule, ui.FILL)
      end
      lu.assertEquals({ sizes[2].Value, sizes[3].Value, sizes[4].Value }, { 1.0, 2.0, 1.0 })
      lu.assertEquals(#paddings, 2) -- none on the first pane
      lu.assertEquals(paddings[1], { Left = 24.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
      lu.assertTrue(isFloats(paddings[1].Left, paddings[1].Top, paddings[1].Right, paddings[1].Bottom))
    end,

    testAPaneHasTheSameWidgetsAsThePage = function()
      local page = newPage()
      local left = page:columns({ 1, 2 })[1]
      for _, name in ipairs({ "text", "input", "row", "list", "grid", "space", "clear" }) do
        lu.assertEquals(type(left[name]), "function", name)
      end
      lu.assertNil(left.columns) -- no columns inside a pane
      local row = left:row()
      lu.assertEquals(type(row.space), "function")
      left:text("hello"):set("changed")
      left:space(8)
      lu.assertFalse(pcall(function()
        left:space(0)
      end))
    end,

    testAPageThatIsGoneHandsOutInertPanesWithEveryMethod = function()
      local page, session = newPage()
      session.alive = false
      local built = #fake.widgets
      local panes = page:columns({ 1, 2, 3 })
      lu.assertEquals(#panes, 3)
      for _, pane in ipairs(panes) do
        pane:text("x"):color(1, 1, 1)
        lu.assertEquals(pane:input():get(), "")
        local row = pane:row()
        row:text("x")
        row:item("Wood")
        row:space(4)
        row:button("b", function() end):enable(true)
        row:arrow("next", function() end):enable(true)
        local list = pane:list()
        list:clear()
        list:row():space(4)
        local grid = pane:grid()
        grid:clear()
        grid:tile("Wood")
        pane:space(4)
        pane:clear()
      end
      page:space(4)
      page:row():space(4)
      lu.assertEquals(#fake.widgets, built) -- nothing was built
      -- A bad size is still refused up front, so a mod finds the mistake whatever the page's state.
      lu.assertFalse(pcall(function()
        page:columns({ 1 })
      end))
    end,

    testClearKillsOnlyThatPanesHandlesClicksAndInputs = function()
      local page, session, router = newPage()
      local panes = page:columns({ 1, 2 })
      local left, right = panes[1], panes[2]
      local seen = {}
      local function build(pane, label)
        local text = pane:text(label)
        local input = pane:input({
          onChange = function(value)
            seen[#seen + 1] = label .. value
          end,
        })
        local grid = pane:grid()
        grid:tile("Wood", { onClick = function() end })
        pane:row():button("go", function() end)
        return { text = text, input = input, grid = grid }
      end
      local oldLeft = build(left, "left")
      local oldRight = build(right, "right")
      lu.assertEquals(#session.inputs, 2)
      local before = countClicks(router)
      lu.assertEquals(before, 4) -- a tile and a button in each pane

      local leftBox = ofClass(ui.CLASS.vbox)[1]
      left:clear()
      lu.assertEquals(#callsOf(leftBox, "ClearChildren"), 1)
      lu.assertEquals(#callsOf(ofClass(ui.CLASS.vbox)[2], "ClearChildren"), 0) -- the other pane keeps its widgets
      lu.assertEquals(countClicks(router), 2)
      lu.assertEquals(#session.inputs, 1)
      lu.assertTrue(session.alive)

      -- Old handles of the cleared pane do nothing (and say so once); the other pane's keep working.
      local textWidget = ofClass(ui.CLASS.text)[1]
      local setsBefore = #callsOf(textWidget, "SetText")
      oldLeft.text:set("late")
      oldLeft.text:set("later")
      lu.assertEquals(#callsOf(textWidget, "SetText"), setsBefore)
      lu.assertEquals(oldLeft.input:get(), "")
      oldLeft.grid:tile("Wood") -- ignored, no new tile
      oldRight.text:set("still works")
      lu.assertEquals(#callsOf(ofClass(ui.CLASS.text)[2], "SetText"), 2) -- built with it, then set
      local deadLogs = 0
      for _, line in ipairs(fake.logs) do
        if line:find("after its page was rebuilt or closed, or its pane was cleared", 1, true) then
          deadLogs = deadLogs + 1
        end
      end
      lu.assertEquals(deadLogs, 3) -- text, input and grid, once each

      -- The pane is usable again with new handles.
      local newLeft = build(left, "left2")
      lu.assertEquals(countClicks(router), 4)
      lu.assertEquals(#session.inputs, 2)
      newLeft.text:set("fresh")
    end,

    testAPaneInputOfAClearedPaneNeverCallsOnChangeAgain = function()
      local page, session = newPage()
      local left = page:columns({ 1, 2 })[1]
      local calls = 0
      left:input({
        onChange = function()
          calls = calls + 1
        end,
      })
      local walking = session.inputs -- what a poll in progress holds
      lu.assertEquals(#walking, 1)
      left:clear()
      walking[1].onChange("typed after the clear")
      lu.assertEquals(calls, 0)
      lu.assertEquals(#session.inputs, 0)
    end,

    testAPaneCanBeClearedFromTheClickOfItsOwnTile = function()
      local page, _, router = newPage()
      local right = page:columns({ 1, 2 })[2]
      local rebuilt = 0
      local function build()
        local grid = right:grid()
        grid:tile("Wood", {
          onClick = function(name)
            right:clear() -- the tile that was clicked is gone after this
            rebuilt = rebuilt + 1
            right:text("details of " .. name)
            right:grid():tile("Stone", { onClick = function() end })
          end,
        })
      end
      build()
      local tile = ofClass("tile")[1]
      lu.assertTrue(router:route(tile.address, true)) -- the callback ran and nothing broke
      lu.assertEquals(rebuilt, 1)
      for _, line in ipairs(fake.logs) do
        lu.assertNil(line:find("failed", 1, true), line) -- no "click callback failed" line
      end
      lu.assertNil(router.entries[tile.address]) -- the old tile's click is gone
      lu.assertFalse(router:route(tile.address, true)) -- a late second click does nothing
      lu.assertEquals(rebuilt, 1)
      local stone = ofClass("tile")[2]
      lu.assertNotNil(router.entries[stone.address]) -- the new tile is clickable
    end,

    testGameStylesAreCopiedBeforeTheWidgetIsAdded = function()
      local page = newPage()
      page:grid()
      page:list()
      page:input({ hint = "Search" })
      local scrolls = ofClass(ui.CLASS.scroll)
      lu.assertEquals(#scrolls, 2)
      for _, scroll in ipairs(scrolls) do
        local bar, thickness, added =
          writeOf(scroll, "WidgetBarStyle"), writeOf(scroll, "ScrollbarThickness"), addOf(scroll)
        lu.assertNotNil(bar)
        lu.assertNotNil(thickness)
        lu.assertTrue(bar < added and thickness < added)
        lu.assertEquals(scroll.WidgetBarStyle, "bar style")
        lu.assertEquals(scroll.ScrollbarThickness, 22.0)
      end
      local box = ofClass(ui.CLASS.edit)[1]
      lu.assertTrue(writeOf(box, "WidgetStyle") < addOf(box))
      lu.assertEquals(box.WidgetStyle, "search style")
      lu.assertEquals(callsOf(box, "SetHintText")[1][1], "Search") -- the hint still works with the style
    end,

    testAMissingStyleTemplateKeepsTheEngineDefaultAndLogsOncePerPage = function()
      fake.missing[ui.SCROLL_TEMPLATE] = true
      fake.missing[ui.SEARCH_TEMPLATE] = true
      local page = newPage()
      page:grid()
      page:list()
      page:input()
      page:input()
      lu.assertNil(writeOf(ofClass(ui.CLASS.scroll)[1], "WidgetBarStyle"))
      lu.assertNil(writeOf(ofClass(ui.CLASS.edit)[1], "WidgetStyle"))
      lu.assertEquals(#ofClass(ui.CLASS.scroll), 2) -- the widgets are still made
      lu.assertEquals(logsWith("scrollbar style was not found"), 1)
      lu.assertEquals(logsWith("search box style was not found"), 1)
    end,

    testSmallButtonsAreScaledAndPaddedAndArrowsKeepTheirScale = function()
      local page = newPage()
      local row = page:row()
      row:button("Add", function() end, { small = true })
      local boxes = ofClass(ui.CLASS.scale)
      lu.assertEquals(callsOf(boxes[1], "SetUserSpecifiedScale")[1][1], 0.7)
      local border = ofClass("ContentBorder")[1]
      lu.assertEquals(callsOf(border, "SetPadding")[1][1], { Left = 10.0, Top = 0.0, Right = 10.0, Bottom = 0.0 })
      row:arrow("next", function() end)
      lu.assertEquals(callsOf(ofClass(ui.CLASS.scale)[2], "SetUserSpecifiedScale")[1][1], 0.6)
    end,

    testBadDividerHeadingsAreRejectedAtTheModsCall = function()
      local page = newPage()
      local pane = page:columns({ 1, 2 })[1]
      local built = #fake.widgets
      for _, value in ipairs({ "", 5, true, {} }) do
        for _, target in ipairs({ page, pane }) do
          local ok, message = pcall(function()
            target:divider(value)
          end)
          lu.assertFalse(ok)
          lu.assertStrContains(message, "test_ui_layout.lua")
          lu.assertStrContains(message, ":divider takes an optional heading as text")
        end
      end
      lu.assertEquals(#fake.widgets, built)
    end,

    testAHeadingDividerSetsShowTextBeforeItIsAddedAndAPlainOneCollapsesItsText = function()
      local page = newPage()
      page:divider("Cauldron")
      page:divider()
      local dividers = ofClass("divider")
      lu.assertEquals(#dividers, 2)
      lu.assertEquals(dividers[1].ShowText, "Cauldron")
      lu.assertTrue(writeOf(dividers[1], "ShowText") < addOf(dividers[1]))
      lu.assertEquals(callsOf(dividers[2].Txt_BuildOptionType, "SetVisibility")[1][1], 1)
      lu.assertNil(writeOf(dividers[2], "ShowText"))
      lu.assertEquals(#ofClass(ui.CLASS.sizeBox), 0) -- no solid line was needed
    end,

    testWithoutTheGameDividerAHorizontalSolidLineTakesItsPlaceAndIsLoggedOnce = function()
      fake.missing[ui.CLASS.divider] = true
      local page = newPage()
      local pane = page:columns({ 1, 2 })[1]
      page:divider("Cauldron")
      page:divider()
      pane:divider()
      local boxes = ofClass(ui.CLASS.sizeBox)
      lu.assertEquals(#boxes, 3)
      lu.assertEquals(callsOf(boxes[1], "SetHeightOverride")[1][1], 2.0)
      lu.assertEquals(#callsOf(boxes[1], "SetWidthOverride"), 0)
      lu.assertEquals(callsOf(ofClass(ui.CLASS.image)[1], "SetColorAndOpacity")[1][1], ui.LINE)
      lu.assertEquals(logsWith("the game's divider could not be made"), 1)
    end,

    testRowDividersAreAThinVerticalLineThatFillsTheRowWithRoomOnBothSides = function()
      local page = newPage()
      local list = page:list()
      for _, row in ipairs({ page:row(), list:row() }) do
        row:text("a")
        row:divider()
        row:text("b")
      end
      local boxes = ofClass(ui.CLASS.sizeBox)
      lu.assertEquals(#boxes, 2)
      for _, box in ipairs(boxes) do
        lu.assertEquals(callsOf(box, "SetWidthOverride")[1][1], 2.0)
        lu.assertEquals(#callsOf(box, "SetHeightOverride"), 0)
      end
      local image = ofClass(ui.CLASS.image)[1]
      lu.assertEquals(callsOf(image, "SetColorAndOpacity")[1][1], { R = 0.478, G = 0.424, B = 0.373, A = 1.0 })
      lu.assertEquals(callsOf(image, "SetVisibility")[1][1], 3)
      local spacers = ofClass(ui.CLASS.spacer)
      lu.assertEquals(#spacers, 4)
      lu.assertEquals(callsOf(spacers[1], "SetSize")[1][1], { X = 16.0, Y = 0.0 })
      local fills = 0
      for _, slot in ipairs(ofClass("slot")) do
        for _, args in ipairs(callsOf(slot, "SetVerticalAlignment")) do
          fills = fills + (args[1] == 0 and 1 or 0)
        end
      end
      lu.assertEquals(fills, 2)
    end,

    testColumnsOptionsAreCheckedAndADividerSplitsTheGap = function()
      local page = newPage()
      local built = #fake.widgets
      for _, opts in ipairs({ true, "x", { divider = "yes" }, { divider = true, other = 1 }, { other = true } }) do
        local ok, message = pcall(function()
          page:columns({ 1, 2 }, opts)
        end)
        lu.assertFalse(ok)
        lu.assertStrContains(message, "test_ui_layout.lua")
        lu.assertStrContains(message, "page:columns takes an optional second argument")
      end
      lu.assertEquals(#fake.widgets, built)
      page:columns({ 1, 2 }, { divider = false }) -- same as no options
      lu.assertEquals(#ofClass(ui.CLASS.sizeBox), 0)

      local withLine = newPage()
      withLine:columns({ 1, 2 }, { divider = true })
      local boxes = ofClass(ui.CLASS.sizeBox)
      lu.assertEquals(#boxes, 1)
      lu.assertEquals(callsOf(boxes[1], "SetWidthOverride")[1][1], 2.0)
      local halves = 0
      for _, slot in ipairs(ofClass("slot")) do
        for _, args in ipairs(callsOf(slot, "SetPadding")) do
          if args[1].Left == 12.0 then
            halves = halves + 1
          end
        end
      end
      lu.assertEquals(halves, 2) -- 12 before the line, 12 before the second pane
    end,

    testDeadPagesHandOutInertDividers = function()
      local page, session = newPage()
      local pane = page:columns({ 1, 2 })[1]
      local row = page:row()
      session.alive = false
      local built = #fake.widgets
      page:divider("x")
      pane:divider()
      pane:row():divider()
      page:list():row():divider()
      row:divider()
      for _, panes in ipairs(page:columns({ 1, 2 }, { divider = true })) do
        panes:divider("x")
        panes:row():divider()
      end
      lu.assertEquals(#fake.widgets, built)
    end,

    testDroppingThePageDropsThePaneClicksToo = function()
      local page, session, router = newPage()
      local left = page:columns({ 1, 2 })[1]
      left:grid():tile("Wood", { onClick = function() end })
      left:clear()
      left:grid():tile("Wood", { onClick = function() end })
      lu.assertEquals(countClicks(router), 1)
      -- A pane's session names the page's as its parent, so dropping the page drops the pane's entries as well.
      session.alive = false
      router:dropSession(session)
      lu.assertEquals(countClicks(router), 0)
    end,
  },
}
