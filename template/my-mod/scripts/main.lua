-- My Mod: a starting point. Copy this folder, rename it, and change "id" and "name" in mod.json.
-- It adds one tab to the TAB menu (colored and wrapped text, a text box, buttons, a grid of clickable item tiles
-- and a list) and one console command. See docs/api.md in af-modloader-api for everything the API offers.

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
    -- Colors are numbers from 0 to 1 (r, g, b, a). A gold heading:
    local heading = page:text(message)
    heading:color(1.0, 0.75, 0.2, 1.0)

    -- A long line wraps at the panel's edge with { wrap = true }. Without it the line runs past the edge.
    page:text("A long line of text wraps inside the panel instead of running past its edge.", { wrap = true })

    -- The world that is loaded now (the player's save), or nil at the main menu. The page is built when the menu
    -- opens, so this is always current.
    local world = api.world.current()
    page:text(world and ("World: " .. world.title) or "No world loaded")

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

    -- A disabled button is grey and ignores clicks. Call enable() after the button is in its row, and keep the
    -- handle to enable it later. Texts in a row can be colored too.
    local lockedRow = page:row()
    lockedRow:text("Locked: "):color(0.7, 0.7, 0.7, 1.0)
    local locked = lockedRow:button("Locked", function()
      message = "The unlocked button was clicked"
      heading:set(message)
    end)
    locked:enable(false)
    lockedRow:button("Unlock", function()
      locked:enable(true)
    end)

    -- Small text and a small button: size = "small" and { small = true } draw them smaller (a small text cannot
    -- wrap). An arrow button has a direction, "previous" or "next", and enable() greys it at the ends.
    page:text("A small line of text", { size = "small" })
    local pagerRow = page:row()
    pagerRow:button("Small", function()
      message = "The small button was clicked"
      heading:set(message)
    end, { small = true })
    local PAGES, shown = 3, 1
    local previousArrow, nextArrow
    local pageLabel = pagerRow:text("", { size = "small" })
    local function showPager()
      pageLabel:set(string.format("Page %d of %d", shown, PAGES))
      previousArrow:enable(shown > 1)
      nextArrow:enable(shown < PAGES)
    end
    previousArrow = pagerRow:arrow("previous", function()
      shown = shown - 1
      showPager()
    end)
    pagerRow:text(" ", { size = "small" })
    nextArrow = pagerRow:arrow("next", function()
      shown = shown + 1
      showPager()
    end)
    showPager()

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

-- Runs on the game thread each time a world is loaded and its name is known. Like tabs, it can only be added here.
-- world.key is safe to use in a file name, and world.generation is different for every load: delayed work should
-- remember it and stop when api.world.current() is nil or has another generation (see docs/api.md).
api.world.onEnter(function(world)
  AF.log("My Mod: world loaded: " .. world.title .. " (key " .. world.key .. ")")
end)

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
