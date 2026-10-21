-- The in-game console: turns it on when a mod needs it, and connects the mods' commands to it. Game-facing, tested
-- in game; the command dispatch and the opt-out rules are in commands.lua (tested without the game).
--
-- Enabling the console follows the technique of ConsoleEnablerMod from UE4SS (https://github.com/UE4SS-RE/RE-UE4SS),
-- which is MIT licensed:
--
--   MIT License
--   Copyright (c) 2022 Narknon
--   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
--   documentation files (the "Software"), to deal in the Software without restriction, including without limitation
--   the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
--   to permit persons to whom the Software is furnished to do so, subject to the following conditions:
--   The above copyright notice and this permission notice shall be included in all copies or substantial portions of
--   the Software.
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
--   THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
--   CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
--   IN THE SOFTWARE.
--
local commands = require("commands")
local hooks = require("hooks")
local ui = require("ui")

local console = {}
local Console = {}
Console.__index = Console

local OPT_OUT_FILE = "af-modloader-api.json"
local CONSOLE_KEYS = { "Tilde", "F10" }
local RESTART_HOOK = "/Script/Engine.PlayerController:ClientRestart"

local isValid = ui.isValid

local function engine()
  local okHelpers, helpers = pcall(require, "UEHelpers")
  if okHelpers and type(helpers) == "table" and helpers.GetEngine then
    local ok, found = pcall(helpers.GetEngine)
    if ok and isValid(found) then
      return found
    end
  end
  local found = FindFirstOf("GameEngine")
  if isValid(found) then
    return found
  end
end

-- Adds the console keys that are not set yet. Returns the names it added.
local function addConsoleKeys()
  local settings = StaticFindObject("/Script/Engine.Default__InputSettings")
  if not isValid(settings) then
    error("Default__InputSettings was not found")
  end
  local keys = settings.ConsoleKeys
  local added = {}
  for _, keyName in ipairs(CONSOLE_KEYS) do
    local name = FName(keyName)
    local present = false
    for index = 1, #keys do
      if keys[index].KeyName == name then
        present = true
        break
      end
    end
    if not present then
      keys[#keys + 1].KeyName = name
      added[#added + 1] = keyName
    end
  end
  return added
end

-- Makes sure the game viewport has a console. Returns "ready" once it does, or nil and why not yet.
local function ensureViewportConsole()
  local found = engine()
  if not found then
    return nil, "the game engine object is not available yet"
  end
  local viewport = found.GameViewport
  if not isValid(viewport) then
    return nil, "the game viewport does not exist yet"
  end
  if not isValid(viewport.ViewportConsole) then
    local class = StaticFindObject("/Script/Engine.Console")
    if not isValid(class) then
      error("/Script/Engine.Console was not found")
    end
    local created = StaticConstructObject(class, viewport)
    if not isValid(created) then
      error("could not create the console object")
    end
    viewport.ViewportConsole = created
  end
  addConsoleKeys()
  return "ready"
end

-- options: { registry, dispatcher, log, dataDir, decode = AF.json.decode }
function console.new(options)
  local self = setmetatable({}, Console)
  self.registry = options.registry
  self.dispatcher = options.dispatcher
  self.log = options.log
  self.optOutPath = options.dataDir .. "\\" .. OPT_OUT_FILE
  self.decode = options.decode
  self.decision = nil -- nil: not decided yet, true: console on, false: console off
  self.ready = false
  return self
end

-- Registers one UE4SS handler for the command name and one for its uppercase alias. UE4SS runs every handler of a
-- name, so each name gets exactly one, and the dispatcher does the rest.
function Console:register(entry)
  local names = { entry.name }
  if entry.alias then
    names[#names + 1] = entry.alias
  end
  for _, name in ipairs(names) do
    local ok, problem = pcall(RegisterConsoleCommandGlobalHandler, name, function(fullCommand, params, device)
      -- Precaution (the spike's handler did the same): answer only when the first word is this name.
      local typed = tostring(fullCommand):match("^%s*(%S+)")
      if typed and typed ~= name then
        return false
      end
      local okRun, handled = pcall(function()
        return self.dispatcher:dispatch(name, params, device)
      end)
      if not okRun then
        self.log("command " .. name .. " could not run: " .. tostring(handled))
        return false
      end
      return handled
    end)
    if not ok then
      self.log(
        string.format("could not register the console command %s (mod %s): %s", name, entry.owner, tostring(problem))
      )
    end
  end
end

local function readFile(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read("a")
  file:close()
  return text
end

-- Decides once, after every mod has registered its commands: is the console needed, and may it be turned on?
function Console:decide()
  if self.decision ~= nil then
    return
  end
  local owners = self.registry:consoleNeededBy()
  if #owners == 0 then
    self.decision = false
    self.log("console: no mod added a command, so the in-game console stays as the game ships it (off)")
    return
  end
  local enabled, note = commands.parseOptOut(readFile(self.optOutPath), self.decode)
  if note then
    self.log("console: " .. self.optOutPath .. ": " .. note)
  end
  if not enabled then
    self.decision = false
    self.log(
      string.format(
        'console: left off because %s says so ("console": false). Commands from %s cannot be used in game. '
          .. "Delete that file or set it to true to turn the console on.",
        self.optOutPath,
        table.concat(owners, ", ")
      )
    )
    return
  end
  self.decision = true
  self.log(
    string.format(
      "console: turning on the in-game console because %s added commands. "
        .. 'Open it with F10 or the key left of 1. To keep it off, write { "console": false } in %s',
      table.concat(owners, ", "),
      self.optOutPath
    )
  )
end

-- Runs at every PlayerController:ClientRestart and every InitGameState (all entrypoints have run by then): decide
-- once, then make sure the viewport console exists, and stop trying once it does.
function Console:onGameStart()
  self.registry:seal()
  self:decide()
  if not self.decision or self.ready then
    return
  end
  local ok, result, why = pcall(ensureViewportConsole)
  if not ok then
    self.log("console: could not be turned on: " .. tostring(result))
  elseif result == "ready" then
    self.ready = true
    self.log("console: ready")
  else
    self.log("console: not ready yet (" .. tostring(why) .. "), trying again at the next restart of the player")
  end
end

function Console:install()
  local function trigger()
    local ok, problem = pcall(function()
      self:onGameStart()
    end)
    if not ok then
      self.log("console: " .. tostring(problem))
    end
  end
  hooks.install({
    {
      path = RESTART_HOOK,
      effect = "The console may only be turned on by the other trigger (a new game state).",
      fn = trigger,
    },
  }, self.log)
  -- Second trigger, in case ClientRestart does not fire: the loader verified that this one does. The decision still
  -- runs only once.
  local ok, problem = pcall(RegisterInitGameStatePostHook, trigger)
  if not ok then
    self.log("console: could not hook the start of the game state: " .. tostring(problem))
  end
end

return console
