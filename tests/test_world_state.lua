-- Contract of the world state: what a mod sees as "the current world" across game state changes, with no game.
local lu = require("luaunit")
local world_state = require("world_state")

local MENU = { preview = true, title = "" }
local MENU_AFTER_WORLD = { preview = true, title = "Prueba_2609125624" } -- the menu keeps the last title
local function loaded(title)
  return { preview = false, title = title }
end

return {
  TestWorldState = {
    testMenuHasNoWorld = function()
      local state = world_state.new()
      local event, why = state:onInitGameState(MENU)
      lu.assertEquals({ event, why }, { "none", "menu" })
      lu.assertNil(state:current())
    end,

    testLoadEntersWithTitleKeyAndGeneration = function()
      local state = world_state.new()
      local event, world = state:onInitGameState(loaded("My World_1"))
      lu.assertEquals(event, "enter")
      lu.assertEquals(world, { title = "My World_1", key = "My~20World_1", generation = 1 })
      lu.assertEquals(state:current(), world)
    end,

    testCurrentIsACopy = function()
      local state = world_state.new()
      state:onInitGameState(loaded("A_1"))
      local copy = state:current()
      copy.title = "changed"
      lu.assertEquals(state:current().title, "A_1")
    end,

    testReloadOfTheSameWorldGetsANewGeneration = function()
      local state = world_state.new()
      local _, first = state:onInitGameState(loaded("A_1"))
      local _, second = state:onInitGameState(loaded("A_1"))
      lu.assertEquals(second.key, first.key)
      lu.assertNotEquals(second.generation, first.generation)
    end,

    testBackToTheMenuClearsTheWorldEvenWithTheOldTitle = function()
      local state = world_state.new()
      state:onInitGameState(loaded("Prueba_2609125624"))
      local event = state:onInitGameState(MENU_AFTER_WORLD)
      lu.assertEquals(event, "none")
      lu.assertNil(state:current())
    end,

    testNewGameAfterAnotherWorldIsItsOwnWorld = function()
      local state = world_state.new()
      local _, a = state:onInitGameState(loaded("Prueba_2609125624"))
      local _, b = state:onInitGameState(loaded("new_2610216118"))
      lu.assertEquals(b.title, "new_2610216118")
      lu.assertNotEquals(b.generation, a.generation)
    end,

    testEmptyTitleWhileNotInPreviewIsNoWorld = function()
      local state = world_state.new()
      state:onInitGameState(loaded("A_1"))
      local event, why = state:onInitGameState(loaded(""))
      lu.assertEquals({ event, why }, { "none", "unnamed" })
      lu.assertNil(state:current())
    end,

    testUnreadableGameIsNoWorld = function()
      local state = world_state.new()
      local event, why = state:onInitGameState(nil)
      lu.assertEquals({ event, why }, { "none", "unreadable" })
    end,

    testEveryInitGameStateBumpsTheEpoch = function()
      local state = world_state.new()
      local before = state:epoch()
      state:onInitGameState(MENU)
      state:onInitGameState(MENU)
      lu.assertEquals(state:epoch(), before + 2)
    end,

    testDelayedReadEntersWhenNothingHappenedSince = function()
      local state = world_state.new()
      local event, world = state:onDelayedRead(state:epoch(), loaded("A_1"))
      lu.assertEquals(event, "enter")
      lu.assertEquals(world.title, "A_1")
    end,

    testDelayedReadWithAnOldEpochIsIgnored = function()
      local state = world_state.new()
      local epoch = state:epoch()
      state:onInitGameState(MENU)
      local event, why = state:onDelayedRead(epoch, loaded("A_1"))
      lu.assertEquals({ event, why }, { "none", "stale" })
      lu.assertNil(state:current())
    end,

    testDelayedReadDoesNotReplaceACurrentWorld = function()
      local state = world_state.new()
      local epoch = state:epoch()
      state:onDelayedRead(epoch, loaded("A_1"))
      local event, why = state:onDelayedRead(epoch, loaded("A_1"))
      lu.assertEquals({ event, why }, { "none", "stale" })
      lu.assertEquals(state:current().generation, 1)
    end,

    testDelayedReadAtTheMenuOnlyDoesNothing = function()
      local state = world_state.new()
      local event = state:onDelayedRead(state:epoch(), MENU)
      lu.assertEquals(event, "none")
    end,
  },

  TestWorldDispatch = {
    testCallbacksRunInOrderWithTheirOwnCopyAndAnErrorDoesNotStopTheNext = function()
      local order, logs, seen = {}, {}, {}
      local entries = {
        {
          owner = "mod-a",
          fn = function(world)
            order[#order + 1] = "a"
            world.title = "changed by a"
          end,
        },
        {
          owner = "mod-b",
          fn = function()
            order[#order + 1] = "b"
            error("boom")
          end,
        },
        {
          owner = "mod-c",
          fn = function(world)
            order[#order + 1] = "c"
            seen = world
          end,
        },
      }
      world_state.dispatch(entries, { title = "T_1", key = "T_1", generation = 3 }, function(text)
        logs[#logs + 1] = text
      end)
      lu.assertEquals(order, { "a", "b", "c" })
      lu.assertEquals(seen, { title = "T_1", key = "T_1", generation = 3 })
      lu.assertEquals(#logs, 1)
      lu.assertStrContains(logs[1], "mod-b")
      lu.assertStrContains(logs[1], "boom")
    end,
  },
}
