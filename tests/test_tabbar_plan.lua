-- Contract of the tab bar plan: which tabs show when they do not all fit, and how the arrows move the window.
local lu = require("luaunit")
local plan = require("tabbar_plan")

-- The widths measured in game 1.1.5024 (docs/tab-menu.md) and the room left by the page box (580 - 16 - 2 * 68).
local MEASURED = { 128, 128, 154, 199, 128 }
local AVAILABLE = 564

local function options(widths, overrides)
  local value = { count = #widths, widths = widths, available = AVAILABLE, arrow = 64, gap = 4 }
  for key, item in pairs(overrides or {}) do
    value[key] = item
  end
  return value
end

local function shown(window)
  return { window.first, window.last, window.paged, window.canPrev, window.canNext }
end

-- Follows a list of clicks from the first window and returns "first-last" after each.
local function walk(widths, clicks)
  local current = plan.window(options(widths))
  local seen = {}
  for _, direction in ipairs(clicks) do
    current = plan.step(options(widths, { first = current.first }), direction)
    seen[#seen + 1] = current.first .. "-" .. current.last
  end
  return seen
end

return {
  TestTabbarWindow = {
    testEveryTabFitsMeansNoPaging = function()
      lu.assertEquals(shown(plan.window(options({ 128, 128, 154, 128 }))), { 1, 4, false, false, false })
    end,

    testTabsThatDoNotFitPage = function()
      -- 737 wide in 564: room for tabs is 428, so 128 + 128 + 154 fit and 199 does not.
      lu.assertEquals(shown(plan.window(options(MEASURED))), { 1, 3, true, false, true })
    end,

    testUnknownWidthsCountAsTheTabMinimum = function()
      -- 5 tabs of 128 = 640 > 564; room 428 holds 3 tabs of 128.
      local window = plan.window(options({}, { count = 5 }))
      lu.assertEquals(shown(window), { 1, 3, true, false, true })
      lu.assertEquals(shown(plan.window(options({ 0, 0, 0, 0, 0 }))), { 1, 3, true, false, true })
    end,

    testWindowAtTheEndTakesAsManyTabsAsFit = function()
      -- Starting at tab 5 would leave room: the window moves back so it ends with tab 5 and is full.
      lu.assertEquals(shown(plan.window(options(MEASURED, { first = 5 }))), { 4, 5, true, true, false })
    end,

    testFirstIsClamped = function()
      lu.assertEquals(plan.window(options(MEASURED, { first = 99 })).last, 5)
      lu.assertEquals(plan.window(options(MEASURED, { first = -3 })).first, 1)
    end,
  },

  TestTabbarStep = {
    testNextMovesByWholeViews = function()
      lu.assertEquals(walk(MEASURED, { "next", "next", "next" }), { "3-4", "4-5", "4-5" })
    end,

    testPreviousMovesByWholeViews = function()
      lu.assertEquals(walk(MEASURED, { "next", "next", "previous", "previous", "previous", "previous" }), {
        "3-4",
        "4-5",
        "3-4",
        "2-3",
        "1-3",
        "1-3",
      })
    end,

    testNoClickLeavesAnArrowWithoutChange = function()
      -- At the start "previous" and at the end "next" do nothing (no wrap-around).
      lu.assertEquals(walk(MEASURED, { "previous" }), { "1-3" })
      local atEnd = plan.step(options(MEASURED, { first = 4 }), "next")
      lu.assertEquals(shown(atEnd), { 4, 5, true, true, false })
    end,

    testStepWithoutPagingChangesNothing = function()
      local widths = { 128, 128, 128 }
      lu.assertEquals(shown(plan.step(options(widths), "next")), { 1, 3, false, false, false })
    end,
  },
}
