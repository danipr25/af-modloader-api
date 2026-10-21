-- Contract of the world key: what a world's title becomes in a file name. The table is golden: a change here
-- renames the files of every mod that stores data per world, so it must be deliberate.
local lu = require("luaunit")
local world_key = require("world_key")

local A48 = string.rep("a", 48)

local GOLDEN = {
  { "Prueba_2609125624", "Prueba_2609125624" }, -- plain ASCII is kept
  { "My World", "My~20World" },
  { "Hello World!", "Hello~20World~21" },
  { "a-b_C9", "a-b_C9" },
  { "\xC3\xB1\xC3\xBA_2610216118", "~C3~B1~C3~BA_2610216118" }, -- the verified non-ASCII title (UTF-8 bytes)
  { A48, A48 }, -- exactly 48: kept as it is
  { A48 .. "a", A48 .. "-4e8d2a7c" }, -- over 48: first 48, "-", FNV-1a of the full title
  { "Long World Name " .. string.rep("x", 40), "Long~20World~20Name~20xxxxxxxxxxxxxxxxxxxxxxxxxx-592cf8ba" },
}

return {
  TestWorldKey = {
    testGoldenKeys = function()
      for _, case in ipairs(GOLDEN) do
        lu.assertEquals(world_key.make(case[1]), case[2], "title " .. case[1])
      end
    end,

    testFnv1aKnownValue = function()
      lu.assertEquals(world_key.fnv1a("a"), "e40c292c")
      lu.assertEquals(world_key.fnv1a(""), "811c9dc5")
    end,

    testSameTitleSameKeyAndPrefixesDiffer = function()
      lu.assertEquals(world_key.make(A48 .. "1"), world_key.make(A48 .. "1"))
      lu.assertNotEquals(world_key.make(A48 .. "1"), world_key.make(A48 .. "2"))
    end,

    testKeysAreAsciiFileNames = function()
      local key = world_key.make('\xC3\xB1 /  : * ? " < > |' .. string.rep("\xC3\xBA", 40))
      lu.assertNil(key:find("[^A-Za-z0-9_~%-]"))
      lu.assertTrue(#key <= 48 + 9)
    end,
  },
}
