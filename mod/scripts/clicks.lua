-- Routes clicks on the widgets the API created to the mod callback that asked for them. Pure Lua with no game access
-- (tests/test_clicks.lua): tabs.lua feeds it the address of the clicked widget from the game's hooks.
--
-- The hooks fire for every tile and every CommonUI button in the game, so most calls are for widgets that are not
-- ours. Those return at once and write nothing. Entries are keyed by the widget's address and removed when their
-- page is rebuilt (dropSession), when the panel changes (reset) or when a grid is cleared (forget). A stale entry
-- is also refused by its own alive() check before a callback runs, and an address the game reuses is replaced by
-- the new owner's entry.
local clicks = {}

local Router = {}
Router.__index = Router

function clicks.new(log)
  return setmetatable({ entries = {}, log = log }, Router)
end

-- entry: { owner = mod id for logs, session = the page session it belongs to (or nil), alive = function() -> bool
--          (optional, false means the widget is gone), fn = function() the mod's callback }
function Router:register(address, entry)
  if address ~= nil then
    self.entries[address] = entry
  end
end

function Router:forget(address)
  self.entries[address] = nil
end

-- Removes every entry that belongs to a page session (called when that page is rebuilt).
function Router:dropSession(session)
  for address, entry in pairs(self.entries) do
    if entry.session == session then
      self.entries[address] = nil
    end
  end
end

function Router:reset()
  self.entries = {}
end

-- Calls the callback registered for the widget at 'address', only while 'open' is true (the TAB menu is open and its
-- panel is valid). Returns true when a callback ran. An error in the callback is contained and logged.
function Router:route(address, open)
  if not open or address == nil then
    return false
  end
  local entry = self.entries[address]
  if entry == nil then
    return false
  end
  if entry.alive and not entry.alive() then
    self.entries[address] = nil
    return false
  end
  local ok, problem = xpcall(entry.fn, debug.traceback)
  if not ok then
    self.log(string.format("mod %s: a click callback failed: %s", tostring(entry.owner), tostring(problem)))
  end
  return true
end

return clicks
