-- The API mod and the template must load together with the loader's rules. The game is
-- replaced by stubs here, so this only proves that the files load, register what they say, and agree on versions.
local lu = require("luaunit")

local function readFile(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("a")
  file:close()
  return text
end

-- Loads a mod the way the loader does: its own environment, and require() reading from the scripts folder.
local function loadMod(dir, AF, globals)
  local env = setmetatable({ AF = AF }, { __index = globals })
  env._G = env
  local cache = {}
  env.require = function(name)
    if cache[name] == nil then
      local chunk = assert(loadfile(dir .. "/scripts/" .. name:gsub("%.", "/") .. ".lua", "t", env))
      cache[name] = chunk(name) or true
    end
    return cache[name]
  end
  local chunk = assert(loadfile(dir .. "/scripts/main.lua", "t", env))
  return chunk()
end

local function setup()
  local logs, hooks, handlers, unload = {}, {}, {}, {}
  local initHooks = {}
  local exports = {}
  local stubs = {
    RegisterHook = function(path, fn)
      hooks[path] = fn
    end,
    RegisterInitGameStatePostHook = function(fn)
      initHooks[#initHooks + 1] = fn
    end,
    RegisterConsoleCommandGlobalHandler = function(name, fn)
      handlers[name] = fn
    end,
    ExecuteWithDelay = function() end,
    ExecuteInGameThread = function() end,
    FindFirstOf = function() end, -- no GameSaveLoadSubsystem: the world is nil
  }
  for name, value in pairs(_G) do
    stubs[name] = stubs[name] or value
  end
  local function newAF(modId, depends)
    return {
      modId = modId,
      dataDir = "C:\\nowhere",
      json = { decode = function() end },
      log = function(text)
        logs[#logs + 1] = "[" .. modId .. "] " .. text
      end,
      onUnload = function(fn)
        unload[#unload + 1] = fn
      end,
      require = function(id)
        assert(depends[id], "not listed in depends: " .. id)
        return exports[id]
      end,
    }
  end
  return {
    logs = logs,
    hooks = hooks,
    handlers = handlers,
    unload = unload,
    initHooks = initHooks,
    exports = exports,
    stubs = stubs,
    newAF = newAF,
  }
end

return {
  TestModsLoad = {
    testApiAndTemplateLoadAndRegisterTheirCommands = function()
      local s = setup()
      s.exports["af-modloader-api"] = loadMod("mod", s.newAF("af-modloader-api", {}), s.stubs)
      local api = s.exports["af-modloader-api"]
      lu.assertEquals(api.version, "0.1.1")

      -- The API hooks the game and registers af.help (and its uppercase alias).
      lu.assertNotNil(s.hooks["/Script/Engine.PlayerController:ClientRestart"])
      lu.assertNotNil(
        s.hooks["/Game/Blueprints/WBP/PlayerGear/WBP_PlayerGearPanel.WBP_PlayerGearPanel_C:BP_OnActivated"]
      )
      lu.assertNotNil(s.hooks["/Script/CommonUI.CommonButtonBase:HandleButtonClicked"])
      lu.assertNotNil(s.handlers["af.help"])
      lu.assertNotNil(s.handlers["AF.HELP"])
      lu.assertEquals(#s.unload, 1)
      lu.assertEquals(#s.initHooks, 2) -- the console trigger and the world

      local depends = { ["af-modloader-api"] = true }
      loadMod("template/my-mod", s.newAF("my-mod", depends), s.stubs)
      lu.assertNotNil(s.handlers["mymod.hello"])

      -- The command reaches the template's run function through the real dispatcher.
      local written = {}
      local device = {
        Log = function(_, text)
          written[#written + 1] = text
        end,
      }
      lu.assertTrue(s.handlers["mymod.hello"]("mymod.hello Ana", { "Ana" }, device))
      lu.assertEquals(written, { "Hello, Ana!" })
      lu.assertFalse(s.handlers["mymod.hello"]("other.command", {}, device)) -- not its name: not handled
    end,

    testWorldReachesModsThroughTheRealApi = function()
      local s = setup()
      local subsystem = {
        IsPreviewScene = false,
        WorldTitleName = "My World_1",
        IsValid = function()
          return true
        end,
        GetFullName = function()
          return "GameSaveLoadSubsystem /Engine/Transient.GameInstance_0:GameSaveLoadSubsystem_0"
        end,
      }
      s.stubs.FindFirstOf = function()
        return subsystem
      end
      s.exports["af-modloader-api"] = loadMod("mod", s.newAF("af-modloader-api", {}), s.stubs)
      local api = s.exports["af-modloader-api"].use(s.newAF("my-mod", { ["af-modloader-api"] = true }))
      lu.assertNil(api.world.current())
      local entered
      -- Registered in the entrypoint (before any game state), like a real mod does.
      s.exports["af-modloader-api"].use(s.newAF("other-mod", {})).world.onEnter(function(world)
        entered = world
      end)
      for _, hook in ipairs(s.initHooks) do
        hook()
      end
      lu.assertEquals(api.world.current(), { title = "My World_1", key = "My~20World_1", generation = 1 })
      lu.assertEquals(entered, api.world.current())
    end,

    testVersionsAgree = function()
      local main = readFile("mod/scripts/main.lua")
      local modJson = readFile("mod/mod.json")
      local template = readFile("template/my-mod/mod.json")
      local version = main:match('local VERSION = "([^"]+)"')
      lu.assertEquals(modJson:match('"version": "([^"]+)"'), version)
      lu.assertEquals(modJson:match('"id": "([^"]+)"'), "af-modloader-api")
      -- The template depends on this 0.x line of the API: >=0.N.0 <0.(N+1).0. Raise the lower bound only when the
      -- template needs a call that a later patch version added.
      lu.assertEquals(version:match("^0%.1%."), "0.1.")
      lu.assertStrContains(template, '"af-modloader-api": ">=0.1.0 <0.2.0"')
    end,
  },
}
