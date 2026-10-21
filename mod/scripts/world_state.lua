-- Which world is loaded, decided from what the game shows at each InitGameState. Pure Lua with no game access, so
-- it is tested without the game (tests/test_world_state.lua). world.lua reads the game and feeds this.
local world_key = require("world_key")

local world_state = {}

local State = {}
State.__index = State

-- options: { key = function(title) -> text } (default: world_key.make)
function world_state.new(options)
  local self = setmetatable({}, State)
  self.keyOf = options and options.key or world_key.make
  self.epochNumber = 0 -- bumped at every InitGameState; guards work that was scheduled earlier
  self.generations = 0 -- the public generation: a new number at every enter
  self.world = nil
  return self
end

function State:epoch()
  return self.epochNumber
end

-- A fresh plain copy, or nil when no world is loaded.
function State:current()
  local world = self.world
  if not world then
    return nil
  end
  return { title = world.title, key = world.key, generation = world.generation }
end

-- observation: { preview = boolean, title = text } or nil when the game could not be read.
-- Returns "enter" and the new world, or "none" and why: "unreadable", "menu" or "unnamed".
function State:observe(observation)
  if type(observation) ~= "table" then
    return "none", "unreadable"
  end
  if observation.preview ~= false then
    return "none", "menu"
  end
  local title = observation.title
  if type(title) ~= "string" or title == "" then
    return "none", "unnamed"
  end
  self.generations = self.generations + 1
  self.world = { title = title, key = self.keyOf(title), generation = self.generations }
  return "enter", self:current()
end

-- The game started a new game state (main menu, load, new game, reload). Whatever world was current is gone.
function State:onInitGameState(observation)
  self.epochNumber = self.epochNumber + 1
  self.world = nil
  return self:observe(observation)
end

-- A read scheduled earlier (after a UE4SS mods restart). It only enters: ignored when a game state started since
-- 'epoch' was taken, or when a world is already current.
function State:onDelayedRead(epoch, observation)
  if epoch ~= self.epochNumber or self.world then
    return "none", "stale"
  end
  return self:observe(observation)
end

-- Calls every entry's fn with its own copy of the world, in order. An error is logged and does not stop the next
-- entries. entries: list of { owner, fn }.
function world_state.dispatch(entries, world, log)
  for _, entry in ipairs(entries) do
    local copy = { title = world.title, key = world.key, generation = world.generation }
    local ok, problem = xpcall(entry.fn, debug.traceback, copy)
    if not ok then
      log(string.format("%s: world.onEnter callback failed: %s", entry.owner, tostring(problem)))
    end
  end
end

return world_state
