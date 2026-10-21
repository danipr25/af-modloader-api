-- Console command dispatch and policy. Pure Lua with no game access (tests/test_console_dispatch.lua).
-- UE4SS registers one handler per command name; this module is what each of those handlers calls.
local commands = {}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

-- UE4SS hands the parameters over as a table; turn every item into a plain Lua string.
function commands.plainArgs(params)
  local args = {}
  if type(params) ~= "table" then
    return args
  end
  for index = 1, #params do
    local value = params[index]
    if type(value) == "userdata" then
      local ok, text = pcall(function()
        return value:ToString()
      end)
      value = ok and text or tostring(value)
    end
    args[index] = tostring(value)
  end
  return args
end

-- Reads the player's opt-out file. 'text' is the file content or nil when the file does not exist; 'decode' parses
-- JSON and raises on invalid input. Returns whether the console may be enabled, and a note for the log (or nil).
-- A missing or unusable file means "enabled": only a clear { "console": false } turns it off.
function commands.parseOptOut(text, decode)
  if text == nil then
    return true, nil
  end
  if text:sub(1, 3) == "\239\187\191" then
    text = text:sub(4)
  end
  local ok, value = pcall(decode, text)
  if not ok then
    return true, "the file was ignored because it is not valid JSON (" .. tostring(value):match("^[^\n]*") .. ")"
  end
  if type(value) ~= "table" then
    return true, 'the file was ignored: it must be an object like { "console": false }'
  end
  if value.console == nil then
    return true, nil
  end
  if type(value.console) ~= "boolean" then
    return true, 'the file was ignored: "console" must be true or false'
  end
  return value.console, nil
end

-- registry: a registry object. log: function(text) for the API's own messages.
function commands.new(registry, log)
  return setmetatable({ registry = registry, log = log }, Dispatcher)
end

-- Runs the command the player typed. typed: the registered name (or its uppercase alias), params: UE4SS's parameter
-- table, device: the console output device (device:Log(text) writes to the in-game console).
-- Returns true when the name belongs to a command (UE4SS then stops looking), false otherwise.
function Dispatcher:dispatch(typed, params, device)
  local entry, isAlias = self.registry:findCommand(typed)
  if not entry then
    return false
  end
  local function write(text)
    device:Log(tostring(text))
  end
  if isAlias then
    write("Commands are lowercase: type " .. entry.name)
    return true
  end

  self.log(string.format("console: running %s (mod %s)", entry.name, entry.owner))
  local alive = true
  local function out(text)
    if alive then
      local ok, problem = pcall(write, text)
      if not ok then
        self.log(string.format("%s: could not write to the console: %s", entry.name, tostring(problem)))
      end
    else
      -- The command already returned, so the console line it belonged to is gone. Keep the text in the log.
      self.log(
        string.format(
          "%s (mod %s) wrote to the console after it finished, so it went to the log instead: %s",
          entry.name,
          entry.owner,
          tostring(text)
        )
      )
    end
  end

  local ok, problem = xpcall(entry.run, debug.traceback, commands.plainArgs(params), out)
  alive = false
  if not ok then
    self.log(string.format("mod %s: command %s failed: %s", entry.owner, entry.name, tostring(problem)))
    pcall(write, "Command failed, see UE4SS.log")
  end
  return true
end

-- The spec of the API's own af.help command (listed under the API's mod id).
function commands.helpSpec(registry)
  return {
    name = "af.help",
    help = "Lists the commands added by mods. af.help <name> shows one of them.",
    run = function(args, out)
      if args[1] then
        local entry, isAlias = registry:findCommand(args[1]:lower())
        if entry and not isAlias then
          out(string.format("%s (mod %s): %s", entry.name, entry.owner, entry.help))
        else
          out("No command named " .. args[1] .. ". Type af.help to list the commands.")
        end
        return
      end
      out("Commands added by mods (af.help <name> shows one):")
      for _, entry in ipairs(registry:commands()) do
        out(string.format("  %s (mod %s): %s", entry.name, entry.owner, entry.help))
      end
    end,
  }
end

return commands
