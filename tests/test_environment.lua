-- UE4SS runs Lua 5.4, so local tests must too.
local lu = require("luaunit")

return {
  TestEnvironment = {
    testRunsOnLua54 = function()
      lu.assertEquals(_VERSION, "Lua 5.4")
    end,
  },
}
