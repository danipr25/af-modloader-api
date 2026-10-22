-- Decides what has to be added to a TAB menu panel so that every registered tab is there exactly once. Pure Lua
-- with no game access (tests/test_tabs_plan.lua): tabs.lua reads the live panel into a state table, asks for the
-- plan and applies it.
--
-- The live panel is the only source of truth. Our titles are recognised by their text, and our pages by the page
-- objects this Lua state created, so no counter can drift out of step with the menu.
local plan = {}

local function refuse(reason)
  return { ok = false, reason = reason }
end

-- state:
--   titles     the panel's tab titles, in order (list of text)
--   childCount how many pages the panel's WidgetSwitcher holds
--   tabs       the registered tabs in registration order: { key = ..., title = ... }
--   pageIndex  key -> 0-based index in the WidgetSwitcher of the page we created for that tab (only live pages)
--   pageOffset (optional, default 0) how many more titles than pages the menu has: the TAB menu has one page per
--              title (0); the V menu's Materials and Goods share one page (1). The page of the title at position
--              p (1-based) is then child p - 1 - pageOffset.
-- Returns { ok = true, appendKeys = { keys of the tabs to add, in order } }, or { ok = false, reason = text }.
-- On a refusal nothing must be changed in the panel.
function plan.compute(state)
  local titles, tabs = state.titles, state.tabs
  local offset = state.pageOffset or 0
  local count = #titles
  local firstIndex = {}
  for index, title in ipairs(titles) do
    if firstIndex[title] == nil then
      firstIndex[title] = index
    end
  end

  local present = 0
  for position, tab in ipairs(tabs) do
    local titleAt = firstIndex[tab.title]
    local pageAt = state.pageIndex[tab.key]
    if titleAt and not pageAt then
      return refuse(
        'the menu already has a tab titled "'
          .. tab.title
          .. '" that this run did not create (left over from before a mod restart, or a title the game uses)'
      )
    elseif pageAt and not titleAt then
      return refuse('the page of the tab "' .. tab.title .. '" is in the menu but its title is gone')
    elseif titleAt then
      if position ~= present + 1 then
        return refuse('the tab "' .. tab.title .. '" is in the menu but an earlier registered tab is missing')
      end
      present = position
    end
  end

  -- The tabs already there must be the last ones, in registration order, with their pages in the same places.
  for position = 1, present do
    local expected = count - present + position
    if firstIndex[tabs[position].title] ~= expected or state.pageIndex[tabs[position].key] ~= expected - 1 - offset then
      return refuse('something else was added to the menu around the tab "' .. tabs[position].title .. '"')
    end
  end
  if state.childCount ~= count - offset then
    return refuse(
      string.format(
        "the menu has %d tab titles but %d pages (expected %d), so tabs cannot be matched to pages",
        count,
        state.childCount,
        count - offset
      )
    )
  end

  local appendKeys = {}
  for position = present + 1, #tabs do
    appendKeys[#appendKeys + 1] = tabs[position].key
  end
  return { ok = true, appendKeys = appendKeys }
end

-- Cleanup: the titles to take out of a panel are those of the registered tabs whose page this Lua state created
-- (pageKeys: set of tab keys with a live page). A panel where nothing was added yields an empty list, and the game's
-- own titles are never in it.
function plan.titlesToRemove(tabs, pageKeys)
  local titles = {}
  for _, tab in ipairs(tabs) do
    if pageKeys[tab.key] then
      titles[#titles + 1] = tab.title
    end
  end
  return titles
end

-- Guards page builds against re-entry: tab:refresh() called while a page is being built (for example from inside a
-- build or an onChange that runs during one) is refused with a log line instead of rebuilding under the caller.
local Gate = {}
Gate.__index = Gate

function plan.newGate(log)
  return setmetatable({ building = false, log = log }, Gate)
end

-- Runs fn as a build.
function Gate:run(fn)
  local was = self.building
  self.building = true
  local ok, problem = pcall(fn)
  self.building = was
  if not ok then
    error(problem, 0)
  end
end

-- Runs fn unless a build is going on. Returns whether it ran.
function Gate:request(entry, fn)
  if self.building then
    self.log(
      string.format(
        'mod %s: tab:refresh() for "%s" was ignored because a page is being built. Update the existing handles '
          .. "(text:set, list:clear) instead of refreshing from inside build or onChange.",
        entry.owner,
        entry.title
      )
    )
    return false
  end
  fn()
  return true
end

return plan
