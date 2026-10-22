-- AF Mod Loader API: entrypoint. Mods use it with:
--   local api = AF.require("af-modloader-api").use(AF)
-- See docs/api.md for the contracts and every function.
local commands = require("commands")
local console = require("console")
local registry = require("registry")
local tabs = require("tabs")
local world = require("world")

local VERSION = "0.1.6"

local reg = registry.new({ selfId = AF.modId, version = VERSION, log = AF.log })
local dispatcher = commands.new(reg, AF.log)
local consoleMod = console.new({
  registry = reg,
  dispatcher = dispatcher,
  log = AF.log,
  dataDir = AF.dataDir,
  decode = AF.json.decode,
})
local tabsMod = tabs.new({ registry = reg, log = AF.log })
local worldMod = world.new({ registry = reg, log = AF.log })

reg.onCommandAdded = function(entry)
  consoleMod:register(entry)
end
reg.onTabRefresh = function(entry)
  tabsMod:refresh(entry)
end
reg.worldCurrent = function()
  return worldMod:current()
end

local helpEntry, helpProblem = reg:addCommand(AF.modId, commands.helpSpec(reg))
if not helpEntry then
  error(helpProblem)
end

consoleMod:install()
tabsMod:install()
worldMod:install()
AF.onUnload(function()
  tabsMod:cleanup()
end)

AF.log("AF Mod Loader API " .. VERSION .. " loaded")

return registry.readonly({
  version = VERSION,
  use = function(modAF)
    return reg:use(modAF)
  end,
}, "the AF Mod Loader API")
