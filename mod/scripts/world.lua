-- Tells mods which world is loaded. Game-facing, tested in game: it reads the game's GameSaveLoadSubsystem at every
-- InitGameState and feeds world_state.lua (pure, tested without the game), then calls the mods' onEnter callbacks.
-- The facts it relies on are in docs/world.md.
local ui = require("ui")
local world_state = require("world_state")

local world = {}
local World = {}
World.__index = World

-- After a UE4SS mods restart no InitGameState comes until the next load, so the world is read once, a moment after
-- install (every mod's entrypoint has run by then).
local RESTART_READ_MS = 1000

local isValid = ui.isValid

-- A property value as plain Lua: strings and booleans pass, FString and FName are turned into text.
local function plain(value)
  if type(value) == "userdata" then
    local ok, text = pcall(function()
      return value:ToString()
    end)
    return ok and text or tostring(value)
  end
  return value
end

-- The title as text, or nil when it cannot be read: a world must never be entered with a made-up title.
local function strictText(value)
  if type(value) == "string" then
    return value
  end
  if type(value) == "userdata" then
    local ok, text = pcall(function()
      return value:ToString()
    end)
    if ok and type(text) == "string" then
      return text
    end
  end
  return nil
end

-- What the game shows now: { preview = boolean, title = text, subsystem = object }, or nil when it cannot be read.
local function readSubsystem()
  local subsystem = FindFirstOf("GameSaveLoadSubsystem")
  if not isValid(subsystem) or subsystem:GetFullName():find("Default__", 1, true) then
    return nil
  end
  local title = strictText(subsystem.WorldTitleName)
  if title == nil then
    return nil
  end
  return { preview = plain(subsystem.IsPreviewScene), title = title, subsystem = subsystem }
end

local function safeRead()
  local ok, observation = pcall(readSubsystem)
  if ok then
    return observation
  end
  return nil, tostring(observation)
end

-- options: { registry = the registry (for the onEnter callbacks), log = function(text) }
function world.new(options)
  local self = setmetatable({}, World)
  self.registry = options.registry
  self.log = options.log
  self.state = world_state.new()
  return self
end

-- A copy of the current world, or nil. Used by api.world.current().
function World:current()
  return self.state:current()
end

-- One line per enter, with the extra fields that help in a bug report (each read on its own, so a missing one
-- does not hide the others).
function World:logEnter(entered, subsystem)
  local extra = {}
  for _, field in ipairs({ "NewGameName", "IsStartup", "IsSandbox", "NetSession" }) do
    local ok, value = pcall(function()
      return plain(subsystem[field])
    end)
    extra[#extra + 1] = string.format("%s=%s", field, ok and tostring(value) or "unreadable")
  end
  self.log(
    string.format(
      "world: entered '%s' (key %s, generation %d, %s)",
      entered.title,
      entered.key,
      entered.generation,
      table.concat(extra, ", ")
    )
  )
end

function World:enter(entered, subsystem)
  self:logEnter(entered, subsystem)
  world_state.dispatch(self.registry:worldCallbacks(), entered, self.log)
end

local REASONS = {
  menu = "world: no world loaded (main menu)",
  unnamed = "world: the loaded world has no name yet, so no world is reported",
  unreadable = "world: could not read the game's save state, so no world is reported",
}

function World:onInitGameState()
  local observation, problem = safeRead()
  local event, result = self.state:onInitGameState(observation)
  if event == "enter" then
    self:enter(result, observation.subsystem)
  elseif problem then
    self.log(string.format("world: could not read the game's save state (%s), so no world is reported", problem))
  else
    self.log(REASONS[result])
  end
end

-- The read after install: only enters, and says nothing when there is no world.
function World:onDelayedRead(epoch)
  local observation = safeRead()
  local event, result = self.state:onDelayedRead(epoch, observation)
  if event == "enter" then
    self:enter(result, observation.subsystem)
  end
end

function World:install()
  local ok, problem = pcall(RegisterInitGameStatePostHook, function()
    local okRun, runProblem = pcall(function()
      self:onInitGameState()
    end)
    if not okRun then
      self.log("world: " .. tostring(runProblem))
    end
  end)
  if not ok then
    self.log("world: could not hook the start of the game state, api.world will report no world: " .. tostring(problem))
    return
  end
  local epoch = self.state:epoch()
  ExecuteWithDelay(RESTART_READ_MS, function()
    ExecuteInGameThread(function()
      local okRead, readProblem = pcall(function()
        self:onDelayedRead(epoch)
      end)
      if not okRead then
        self.log("world: " .. tostring(readProblem))
      end
    end)
  end)
end

return world
