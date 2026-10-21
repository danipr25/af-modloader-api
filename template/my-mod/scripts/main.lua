-- My Mod: a starting point. Copy this folder, rename it, and change "id" and "name" in mod.json.
-- It adds one tab to the TAB menu and one console command. See docs/api.md in af-modloader-api for everything the
-- API offers.

local api = AF.require("af-modloader-api").use(AF)

-- Tabs and commands must be added here, while the entrypoint runs, not later from a hook.
local tab = api.tabs.add({
  id = "main",
  title = "My Mod",
  -- build runs on the game thread when the TAB menu is first opened, and again on tab:refresh().
  -- The page and everything created from it are only valid until the next build.
  build = function(page)
    local heading = page:text("Hello from My Mod")

    page:input({
      hint = "Type something",
      onChange = function(text)
        heading:set("You typed: " .. text)
      end,
    })

    local list = page:list()
    local row = list:row()
    row:text("An item from the game: ")
    row:item("GentianNectar", 1) -- the name of an item in the game's data
  end,
})

-- Console commands: lowercase "<namespace>.<name>", with a namespace of at least three characters.
-- The first command added turns the in-game console on (F10), unless the player opted out.
api.console.add({
  name = "mymod.hello",
  help = "Says hello and rebuilds the tab.",
  run = function(args, out)
    out("Hello" .. (args[1] and (", " .. args[1]) or "") .. "!")
    tab:refresh()
  end,
})

AF.log("My Mod loaded")
