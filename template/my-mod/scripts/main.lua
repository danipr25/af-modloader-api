-- My Mod: a starting point. Copy this folder, rename it, and change "id" and "name" in mod.json.
-- It adds one tab to the TAB menu (a text box, a button, a grid of clickable item tiles and a list) and one console
-- command. See docs/api.md in af-modloader-api for everything the API offers.

local api = AF.require("af-modloader-api").use(AF)

local ITEMS = { "GentianNectar", "Wood", "Clay", "Coal" } -- names of items in the game's data
local message = "Hello from My Mod"
local presses = 0
local tab

-- Tabs and commands must be added here, while the entrypoint runs, not later from a hook.
tab = api.tabs.add({
  id = "main",
  title = "My Mod",
  -- build runs on the game thread when the TAB menu is first opened, and again on tab:refresh().
  -- The page and everything created from it are only valid until the next build.
  build = function(page)
    local heading = page:text(message)

    page:input({
      hint = "Type something",
      onChange = function(text)
        message = "You typed: " .. text
        heading:set(message)
      end,
    })

    -- A row on the page: text, item tiles and buttons side by side. A click calls your function.
    local row = page:row()
    row:button("Press me", function()
      presses = presses + 1
      message = "Button pressed " .. presses .. " times"
      tab:refresh() -- a click may rebuild the page: build runs again and shows the new message
    end)

    -- A grid of item tiles that scrolls. Clicking a tile calls onClick with the item name.
    local grid = page:grid()
    local function fillGrid()
      grid:clear()
      for _, name in ipairs(ITEMS) do
        grid:tile(name, {
          onClick = function(clicked)
            message = "You clicked " .. clicked
            heading:set(message)
            fillGrid() -- or update the existing handles: a grid can be cleared and refilled at any time
          end,
        })
      end
    end
    fillGrid()

    local list = page:list()
    local listRow = list:row()
    listRow:text("An item from the game: ")
    listRow:item("GentianNectar", 1)
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
