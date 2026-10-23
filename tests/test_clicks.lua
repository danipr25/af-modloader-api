-- Contract of the click router: a click reaches the callback of the widget the API created, and nothing else.
local lu = require("luaunit")
local clicks = require("clicks")

local function newRouter()
  local logs = {}
  return clicks.new(function(text)
    logs[#logs + 1] = text
  end), logs
end

return {
  TestClicks = {
    testClickOnRegisteredWidgetCallsItsCallbackOnce = function()
      local router = newRouter()
      local calls = 0
      router:register("0x1", {
        owner = "mod-a",
        fn = function()
          calls = calls + 1
        end,
      })
      lu.assertTrue(router:route("0x1", true))
      lu.assertEquals(calls, 1)
    end,

    testUnknownAddressIsIgnoredSilently = function()
      local router, logs = newRouter()
      router:register("0x1", { owner = "mod-a", fn = function() end })
      lu.assertFalse(router:route("0x2", true))
      lu.assertFalse(router:route(nil, true))
      lu.assertEquals(logs, {})
    end,

    testNothingRoutesWhileTheMenuIsNotOpen = function()
      local router = newRouter()
      local calls = 0
      router:register("0x1", {
        owner = "mod-a",
        fn = function()
          calls = calls + 1
        end,
      })
      lu.assertFalse(router:route("0x1", false))
      lu.assertEquals(calls, 0)
    end,

    testDroppedSessionNoLongerRoutes = function()
      local router = newRouter()
      local old, new = {}, {}
      local called = {}
      router:register("0x1", {
        owner = "a",
        session = old,
        fn = function()
          called[#called + 1] = "old"
        end,
      })
      router:register("0x2", {
        owner = "a",
        session = new,
        fn = function()
          called[#called + 1] = "new"
        end,
      })
      router:dropSession(old)
      lu.assertFalse(router:route("0x1", true))
      lu.assertTrue(router:route("0x2", true))
      lu.assertEquals(called, { "new" })
    end,

    testForgetAndResetRemoveEntries = function()
      local router = newRouter()
      router:register("0x1", { owner = "a", fn = function() end })
      router:register("0x2", { owner = "a", fn = function() end })
      router:forget("0x1")
      lu.assertFalse(router:route("0x1", true))
      router:reset()
      lu.assertFalse(router:route("0x2", true))
    end,

    testReusedAddressRoutesToTheNewOwnerOnly = function()
      local router = newRouter()
      local called = {}
      router:register("0x1", {
        owner = "a",
        fn = function()
          called[#called + 1] = "first"
        end,
      })
      router:register("0x1", {
        owner = "b",
        fn = function()
          called[#called + 1] = "second"
        end,
      })
      router:route("0x1", true)
      lu.assertEquals(called, { "second" })
    end,

    testDeadWidgetIsRefusedAndDropped = function()
      local router = newRouter()
      local alive, calls = false, 0
      router:register("0x1", {
        owner = "a",
        alive = function()
          return alive
        end,
        fn = function()
          calls = calls + 1
        end,
      })
      lu.assertFalse(router:route("0x1", true))
      alive = true -- the entry was dropped, so it does not come back
      lu.assertFalse(router:route("0x1", true))
      lu.assertEquals(calls, 0)
    end,

    testDisabledButtonDoesNotRouteUntilEnabledAgain = function()
      local router = newRouter()
      local disabled, calls = true, 0
      router:register("0x1", {
        owner = "a",
        disabled = function()
          return disabled
        end,
        fn = function()
          calls = calls + 1
        end,
      })
      lu.assertFalse(router:route("0x1", true))
      lu.assertEquals(calls, 0)
      disabled = false
      lu.assertTrue(router:route("0x1", true))
      lu.assertEquals(calls, 1)
    end,

    testErrorInCallbackIsContainedAndLoggedWithModId = function()
      local router, logs = newRouter()
      router:register("0x1", {
        owner = "mod-a",
        fn = function()
          error("boom")
        end,
      })
      lu.assertTrue(router:route("0x1", true))
      lu.assertEquals(#logs, 1)
      lu.assertStrContains(logs[1], "mod mod-a")
      lu.assertStrContains(logs[1], "boom")
    end,

    testCallbackMayRemoveEntriesWhileRunning = function()
      local router = newRouter()
      local calls = 0
      router:register("0x1", {
        owner = "a",
        fn = function()
          calls = calls + 1
          router:reset() -- like a click that rebuilds the page
        end,
      })
      lu.assertTrue(router:route("0x1", true))
      lu.assertFalse(router:route("0x1", true))
      lu.assertEquals(calls, 1)
    end,
  },
}
