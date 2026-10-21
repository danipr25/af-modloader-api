-- Contract of command dispatch and the console policy.
local lu = require("luaunit")
local commands = require("commands")
local registry = require("registry")

local function setup()
  local logs = {}
  local function log(text)
    logs[#logs + 1] = text
  end
  local reg = registry.new({ selfId = "af-modloader-api", version = "0.1.0", log = log })
  local dispatcher = commands.new(reg, log)
  local written = {}
  local device = {
    Log = function(_, text)
      written[#written + 1] = text
    end,
  }
  return reg, dispatcher, device, written, logs
end

local function add(reg, owner, name, run, help)
  assert(reg:addCommand(owner, { name = name, help = help or "help of " .. name, run = run }))
end

local function clear(list)
  for index = #list, 1, -1 do
    list[index] = nil
  end
end

return {
  TestDispatch = {
    testRunsTheCommandWithPlainArgsAndOutput = function()
      local reg, dispatcher, device, written = setup()
      local seen
      add(reg, "recipes", "recipes.hello", function(args, out)
        seen = args
        out("hello " .. args[1])
      end)
      lu.assertTrue(dispatcher:dispatch("recipes.hello", { "world", 42 }, device))
      lu.assertEquals(seen, { "world", "42" })
      lu.assertEquals(written, { "hello world" })
    end,

    testUnknownNameIsNotHandled = function()
      local _, dispatcher, device = setup()
      lu.assertFalse(dispatcher:dispatch("recipes.nothing", {}, device))
    end,

    testUppercaseAliasOnlyTellsToUseLowercase = function()
      local reg, dispatcher, device, written = setup()
      local ran = false
      add(reg, "recipes", "recipes.hello", function()
        ran = true
      end)
      lu.assertTrue(dispatcher:dispatch("RECIPES.HELLO", {}, device))
      lu.assertFalse(ran)
      lu.assertEquals(written, { "Commands are lowercase: type recipes.hello" })
    end,

    testAnErrorInACommandIsContained = function()
      local reg, dispatcher, device, written, logs = setup()
      add(reg, "recipes", "recipes.boom", function()
        error("kaboom")
      end)
      lu.assertTrue(dispatcher:dispatch("recipes.boom", {}, device))
      lu.assertEquals(written, { "Command failed, see UE4SS.log" })
      lu.assertStrContains(logs[#logs], "recipes")
      lu.assertStrContains(logs[#logs], "kaboom")
    end,

    testOutputAfterTheCommandFinishedGoesToTheLog = function()
      local reg, dispatcher, device, written, logs = setup()
      local savedOut
      add(reg, "recipes", "recipes.later", function(_, out)
        savedOut = out
      end)
      dispatcher:dispatch("recipes.later", {}, device)
      savedOut("too late")
      lu.assertEquals(written, {})
      lu.assertStrContains(logs[#logs], "too late")
    end,
  },

  TestAfHelp = {
    testListsCommandsWithOwnerAndShowsOne = function()
      local reg, dispatcher, device, written = setup()
      add(reg, "af-modloader-api", "af.help", commands.helpSpec(reg).run)
      add(reg, "recipes", "recipes.hello", function() end, "says hello")

      dispatcher:dispatch("af.help", {}, device)
      local text = table.concat(written, "\n")
      lu.assertStrContains(text, "recipes.hello (mod recipes): says hello")
      lu.assertStrContains(text, "af.help (mod af-modloader-api)")

      clear(written)
      dispatcher:dispatch("af.help", { "recipes.hello" }, device)
      lu.assertEquals(written, { "recipes.hello (mod recipes): says hello" })

      clear(written)
      dispatcher:dispatch("af.help", { "nope.nope" }, device)
      lu.assertStrContains(written[1], "No command named nope.nope")
    end,
  },

  TestConsolePolicy = {
    testOptOutFile = function()
      local decode = function(text)
        if text:find("BROKEN") then
          error("unexpected character")
        end
        if text:find("false") then
          return { console = false }
        elseif text:find("maybe") then
          return { console = "maybe" }
        elseif text:find("scalar") then
          return 42
        end
        return {}
      end
      local cases = {
        { nil, true, false }, -- no file: on, nothing to say
        { '{ "console": false }', false, false },
        { "{}", true, false },
        { "BROKEN", true, true }, -- unreadable: on, with a note
        { '{ "console": "maybe" }', true, true },
        { "scalar", true, true },
      }
      for index, case in ipairs(cases) do
        local enabled, note = commands.parseOptOut(case[1], decode)
        lu.assertEquals(enabled, case[2], "case " .. index)
        lu.assertEquals(note ~= nil, case[3], "case " .. index .. " note")
      end
    end,
  },
}
