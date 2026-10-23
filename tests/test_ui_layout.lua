-- Contract of the layout widgets in ui.lua: page:columns, pane:clear and the spaces. The game is replaced by a small
-- fake that records what is built and which calls reach the slots, so this proves the checks, the numbers sent to
-- the game and the lifetime of panes. How they look in game is not tested here.
local lu = require("luaunit")
local clicks = require("clicks")
local ui = require("ui")

local GLOBALS = { "StaticFindObject", "StaticConstructObject", "FText", "FName", "FindFirstOf" }

-- A widget that records every call and answers the few that return something.
local fake
local function newWidget(class)
  local widget = { class = class, calls = {}, address = #fake.widgets + 1 }
  fake.widgets[#fake.widgets + 1] = widget
  return setmetatable(widget, {
    __index = function(_, name)
      return function(self, ...)
        self.calls[#self.calls + 1] = { name = name, args = { ... } }
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
  fake = { widgets = {}, saved = {}, logs = {} }
  for _, name in ipairs(GLOBALS) do
    fake.saved[name] = _G[name]
  end
  _G.StaticFindObject = function(path)
    return {
      path = path,
      IsValid = function()
        return true
      end,
      Create = function()
        return newWidget("tile")
      end,
    }
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
      local built = #fake.widgets
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
      lu.assertTrue(#fake.widgets >= built)
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
        if line:find("after its page was rebuilt or closed", 1, true) then
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
