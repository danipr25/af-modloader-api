-- Decides which tabs of the TAB menu's tab bar are shown when they do not all fit. Pure Lua with no game access
-- (tests/test_tabbar_plan.lua): tabbar.lua measures the live bar, asks for the window and applies it.
--
-- Tabs move by whole views, never by one tab at a time: "next" makes the tab after the window the last one shown, and
-- "previous" makes the tab before it the first one shown, so no click hides a tab without showing a new one.
local plan = {}

-- A tab is never narrower than this in the game (docs/tab-menu.md). It stands in for a width nobody measured.
plan.MIN_WIDTH = 128

local function widthOf(options, index)
  local width = options.widths[index]
  if type(width) ~= "number" or width <= 0 then
    return plan.MIN_WIDTH
  end
  return width
end

-- The last tab that fits in 'room' when the window starts at 'first'. At least one tab is always shown.
local function lastFrom(options, first, room)
  local used, last = 0, first - 1
  for index = first, options.count do
    used = used + widthOf(options, index)
    if used > room and index > first then
      break
    end
    last = index
  end
  return last
end

-- The first tab such that the tabs from it to 'last' fit in 'room'. At least the last tab alone.
local function firstTo(options, last, room)
  local used, first = 0, last + 1
  for index = last, 1, -1 do
    used = used + widthOf(options, index)
    if used > room and index < last then
      break
    end
    first = index
  end
  return first
end

-- options:
--   count      how many tabs the bar has
--   widths     width of each tab by position (nil or 0 when never measured: counts as MIN_WIDTH)
--   available  the width the bar may use, arrows included
--   arrow      the width of one arrow
--   gap        the space between an arrow and the tabs
--   first      the tab the window starts at (default 1)
-- Returns { paged, first, last, canPrev, canNext }. Paged is false when every tab fits: then the window is all tabs.
function plan.window(options)
  local count = options.count
  local total = 0
  for index = 1, count do
    total = total + widthOf(options, index)
  end
  if count < 1 or total <= options.available then
    return { paged = false, first = 1, last = count, canPrev = false, canNext = false }
  end
  local room = options.available - 2 * (options.arrow + options.gap)
  local first = math.max(1, math.min(options.first or 1, count))
  local last = lastFrom(options, first, room)
  if last == count then
    -- The end of the bar: the window takes as many tabs as fit, ending with the last one.
    first = firstTo(options, count, room)
  end
  return { paged = true, first = first, last = last, canPrev = first > 1, canNext = last < count }
end

-- One arrow click. direction is "next" or "previous". At either end nothing moves (no wrap-around).
-- Returns the new window, which equals the old one when the arrow could not move.
function plan.step(options, direction)
  local current = plan.window(options)
  if not current.paged then
    return current
  end
  local room = options.available - 2 * (options.arrow + options.gap)
  local moved = {}
  for key, value in pairs(options) do
    moved[key] = value
  end
  if direction == "next" and current.canNext then
    moved.first = firstTo(options, current.last + 1, room)
  elseif direction == "previous" and current.canPrev then
    moved.first = current.first - 1
  else
    return current
  end
  return plan.window(moved)
end

return plan
