-- AF Mod Loader API: entrypoint. Mods use it with:
--   local api = AF.require("af-modloader-api").use(AF)
-- See docs/api.md for the contracts and every function.
local catalogSections = require("catalog_sections")
local commands = require("commands")
local console = require("console")
local panels = require("panels")
local registry = require("registry")
local tabs = require("tabs")
local world = require("world")

local VERSION = "0.1.4"

local reg = registry.new({ selfId = AF.modId, version = VERSION, log = AF.log })
local dispatcher = commands.new(reg, AF.log)
local consoleMod = console.new({
  registry = reg,
  dispatcher = dispatcher,
  log = AF.log,
  dataDir = AF.dataDir,
  decode = AF.json.decode,
})
local sectionsMod = catalogSections.new({ registry = reg, log = AF.log })
local catalogMenu = tabs.new({
  registry = reg,
  log = AF.log,
  menu = tabs.CATALOG_MENU,
  onPanelReady = function()
    sectionsMod:ensureHook()
  end,
  onButtonClick = function(address)
    sectionsMod:route(address)
  end,
})
-- The TAB menu's group PreConstruct hook also fires for the V menu's tab bar, which is how the V menu's hooks are
-- registered once its class is loaded.
local tabMenu = tabs.new({
  registry = reg,
  log = AF.log,
  menu = tabs.TAB_MENU,
  onGroupPreConstruct = function()
    catalogMenu:panelMayBeLoaded()
  end,
})
local menus = { tab = tabMenu, catalog = catalogMenu }
local worldMod = world.new({ registry = reg, log = AF.log })
local panelsMod = panels.new({ registry = reg, log = AF.log })

reg.onCommandAdded = function(entry)
  consoleMod:register(entry)
end
reg.onTabRefresh = function(entry)
  menus[entry.menu]:refresh(entry)
end
reg.onTabSelect = function(entry)
  return menus[entry.menu]:select(entry)
end
reg.onPanelTabAdded = function()
  panelsMod:install()
end
reg.onPanelTabRefresh = function(entry)
  panelsMod:refresh(entry)
end
reg.runDeferred = function(owner, fn)
  ExecuteInGameThread(function()
    local ok, problem = xpcall(fn, debug.traceback)
    if not ok then
      AF.log(string.format("mod %s: a deferred function failed: %s", owner, tostring(problem)))
    end
  end)
end
reg.worldCurrent = function()
  return worldMod:current()
end

local helpEntry, helpProblem = reg:addCommand(AF.modId, commands.helpSpec(reg))
if not helpEntry then
  error(helpProblem)
end

consoleMod:install()
tabMenu:install()
catalogMenu:install()
worldMod:install()
AF.onUnload(function()
  panelsMod:cleanup()
  tabMenu:cleanup()
  catalogMenu:cleanup()
end)

AF.log("AF Mod Loader API " .. VERSION .. " loaded")

return registry.readonly({
  version = VERSION,
  use = function(modAF)
    return reg:use(modAF)
  end,
}, "the AF Mod Loader API")
