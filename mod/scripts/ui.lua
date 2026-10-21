-- Page widgets: the handles a mod's build(page) function uses, so mods never touch UMG directly.
-- Game-facing, tested in game. Every call here comes from docs/tab-menu.md or the in-game spike, except those
-- marked "unverified": each of those is wrapped in pcall and falls back to a clear log line.
local ui = {}

local CLASS = {
  vbox = "/Script/UMG.VerticalBox",
  hbox = "/Script/UMG.HorizontalBox",
  scroll = "/Script/UMG.ScrollBox",
  wrap = "/Script/UMG.WrapBox",
  text = "/Script/UMG.TextBlock",
  edit = "/Script/UMG.EditableTextBox",
  tile = "/Game/Blueprints/WBP/Utility/WBP_SimpleItemTile.WBP_SimpleItemTile_C",
  recipeTile = "/Game/Blueprints/WBP/Utility/WBP_RecipeItemTile.WBP_RecipeItemTile_C",
  button = "/Game/Blueprints/WBP/Utility/WBP_ButtonBase.WBP_ButtonBase_C",
  library = "/Script/UMG.Default__WidgetBlueprintLibrary",
}
ui.CLASS = CLASS
ui.FILL = 1 -- ESlateSizeRule::Fill

function ui.isValid(object)
  if object == nil then
    return false
  end
  local ok, valid = pcall(function()
    return object:IsValid()
  end)
  return ok and valid == true
end
local isValid = ui.isValid

function ui.addressOf(object)
  local ok, value = pcall(function()
    return object:GetAddress()
  end)
  return ok and value or nil
end
local addressOf = ui.addressOf

-- Finds a game class that may not be loaded yet: StaticFindObject, then LoadAsset (verified in the spike, where
-- the class was found after LoadAsset). Logs once per class path which way worked, or that it is not available.
-- Returns the class, or nil.
local classNotes = {}
function ui.findClass(path, log)
  local class = StaticFindObject(path)
  local how = "already loaded"
  if not isValid(class) and type(LoadAsset) == "function" then
    how = "loaded with LoadAsset"
    pcall(LoadAsset, path)
    class = StaticFindObject(path)
  end
  local found = isValid(class)
  if classNotes[path] == nil or (found and classNotes[path] == false) then
    classNotes[path] = found
    if found then
      log(string.format("game class %s: %s", path, how))
    else
      log(string.format("game class %s is not available: widgets that need it will fail", path))
    end
  end
  if found then
    return class
  end
end

-- Creates a widget of a UMG class (verified for VerticalBox, TextBlock, EditableTextBox, ScrollBox and WrapBox).
function ui.construct(classPath, outer)
  local class = StaticFindObject(classPath)
  if not isValid(class) then
    error("class not found: " .. classPath)
  end
  local object = StaticConstructObject(class, outer)
  if not isValid(object) then
    error("could not create " .. classPath)
  end
  return object
end

function ui.playerController()
  local okHelpers, helpers = pcall(require, "UEHelpers")
  if okHelpers and type(helpers) == "table" and helpers.GetPlayerController then
    local ok, controller = pcall(helpers.GetPlayerController)
    if ok and isValid(controller) then
      return controller
    end
  end
  local controller = FindFirstOf("PlayerController")
  if isValid(controller) then
    return controller
  end
end

-- ctx: { panel = the WBP_PlayerGearPanel_C, tree = its WidgetTree, root = the page's VerticalBox,
--        owner = mod id for logs, log = function(text), clicks = the click router (clicks.lua),
--        onTileCreated = function(class) called after a tile of that class was made }
-- Returns the page handle for the mod and a session table: session.alive turns false when the page is rebuilt, and
-- session.inputs lists the inputs whose changes must be polled ({ read, last, onChange }).
function ui.newPage(ctx)
  local session = { alive = true, inputs = {} }

  local function aliveCheck(widget, extraCheck)
    return session.alive and (extraCheck == nil or extraCheck()) and isValid(widget)
  end

  -- Returns live(): true while the handle may be used. The first misuse is logged once, then ignored silently.
  local function liveCheck(widget, what, extraCheck)
    local warned = false
    return function()
      if aliveCheck(widget, extraCheck) then
        return true
      end
      if not warned then
        warned = true
        ctx.log(
          string.format(
            "mod %s used a %s after its page was rebuilt or closed: the call was ignored. "
              .. "Handles only work until the next build of the page.",
            ctx.owner,
            what
          )
        )
      end
      return false
    end
  end

  local function makeText(str, add, extraCheck)
    local widget = ui.construct(CLASS.text, ctx.tree)
    widget:SetText(FText(tostring(str)))
    add(widget)
    local live = liveCheck(widget, "text", extraCheck)
    return {
      set = function(_, newText)
        if live() then
          widget:SetText(FText(tostring(newText)))
        end
      end,
    }
  end

  local function makeItem(hbox, name, count, extraCheck)
    if type(name) ~= "string" or name == "" then
      error('row:item needs the item name as text, like "GentianNectar"', 3)
    end
    if count ~= nil and type(count) ~= "number" then
      error("row:item: the count must be a number", 3)
    end
    local library = StaticFindObject(CLASS.library)
    local class = StaticFindObject(CLASS.tile)
    if not isValid(library) or not isValid(class) then
      error("the item tile class of the game was not found")
    end
    local tile = library:Create(ctx.panel, class, ui.playerController())
    if not isValid(tile) then
      error("the game did not create an item tile")
    end
    tile:UpdateItemInfo(FName(name), count or 1, 0, false) -- the count (2nd argument) is verified only with 1
    hbox:AddChildToHorizontalBox(tile)
    return liveCheck(tile, "item tile", extraCheck)
  end

  -- Registers a click callback for a widget. The callback runs in the router's pcall, never inside the hook's.
  local function registerClick(widget, extraCheck, fn)
    local address = addressOf(widget)
    if address == nil then
      ctx.log(string.format("mod %s: a clickable widget has no address, so its clicks will not be noticed", ctx.owner))
      return nil
    end
    ctx.clicks:register(address, {
      owner = ctx.owner,
      session = session,
      alive = function()
        return aliveCheck(widget, extraCheck)
      end,
      fn = fn,
    })
    return address
  end

  local function makeButton(hbox, label, onClick, extraCheck)
    if type(label) ~= "string" or label == "" then
      error('row:button needs the label as text, like "Next"', 3)
    end
    if type(onClick) ~= "function" then
      error("row:button needs a function: row:button(label, function() ... end)", 3)
    end
    local library = StaticFindObject(CLASS.library)
    local class = ui.findClass(CLASS.button, ctx.log)
    if not isValid(library) or not class then
      error("the button class of the game was not found")
    end
    local button = library:Create(ctx.panel, class, ui.playerController())
    if not isValid(button) then
      error("the game did not create a button")
    end
    button:SetButtonText(FText(label))
    hbox:AddChildToHorizontalBox(button)
    registerClick(button, extraCheck, onClick)
    local live = liveCheck(button, "button", extraCheck)
    return {
      set = function(_, newLabel)
        if live() then
          button:SetButtonText(FText(tostring(newLabel)))
        end
      end,
    }
  end

  -- Makes a scroll box fill the rest of the page.
  local function fillSlot(slot, what)
    local okFill = pcall(function()
      slot:SetSize({ Value = 1.0, SizeRule = ui.FILL })
    end)
    if not okFill then
      ctx.log(string.format("the %s could not be set to fill the page: a long one may not scroll", what))
    end
  end

  -- The functions of a horizontal row. extraCheck (optional) says whether the row is still current.
  local function makeRow(hbox, extraCheck, withButtons)
    local rowLive = liveCheck(hbox, "row", extraCheck)
    local row = {}
    function row.text(_, str)
      if not rowLive() then
        return { set = function() end }
      end
      return makeText(str, function(widget)
        hbox:AddChildToHorizontalBox(widget)
      end, extraCheck)
    end
    function row.item(_, name, count)
      if rowLive() then
        makeItem(hbox, name, count, extraCheck)
      end
    end
    if withButtons then
      function row.button(_, label, onClick)
        if not rowLive() then
          return { set = function() end }
        end
        return makeButton(hbox, label, onClick, extraCheck)
      end
    end
    return row
  end

  -- What a dead page or list hands out: the same methods as a live row, doing nothing.
  local inertRow = {
    text = function()
      return { set = function() end }
    end,
    item = function() end,
  }
  local inertPageRow = {
    text = inertRow.text,
    item = inertRow.item,
    button = function()
      return { set = function() end }
    end,
  }
  local pageWarned = false
  -- A page handle kept past the next build of its page does nothing (and says so once).
  local function pageAlive()
    if session.alive then
      return true
    end
    if not pageWarned then
      pageWarned = true
      ctx.log(
        string.format(
          "mod %s used a page handle after its page was rebuilt: the call was ignored. "
            .. "Use the page given to the latest build.",
          ctx.owner
        )
      )
    end
    return false
  end

  local page = {}

  function page.text(_, str)
    if not pageAlive() then
      return { set = function() end }
    end
    return makeText(str, function(widget)
      ctx.root:AddChildToVerticalBox(widget)
    end)
  end

  -- spec: { hint = text shown while empty, onChange = function(text) }
  function page.input(_, spec)
    if not pageAlive() then
      return {
        get = function()
          return ""
        end,
        set = function() end,
      }
    end
    spec = spec or {}
    if type(spec) ~= "table" or (spec.onChange ~= nil and type(spec.onChange) ~= "function") then
      error("page:input takes an optional table { hint = text, onChange = function(text) end }", 2)
    end
    local box = ui.construct(CLASS.edit, ctx.tree)
    if spec.hint then
      local ok = pcall(function() -- unverified: SetHintText
        box:SetHintText(FText(tostring(spec.hint)))
      end)
      if not ok then
        ctx.log("the input hint could not be set (unverified call SetHintText): the box is shown without it")
      end
    end
    ctx.root:AddChildToVerticalBox(box)
    local live = liveCheck(box, "input")
    local function read()
      return box:GetText():ToString() -- unverified: GetText
    end
    local record
    if spec.onChange then
      local okRead, initial = pcall(read)
      record = { read = read, last = okRead and initial or "", onChange = spec.onChange, owner = ctx.owner }
      session.inputs[#session.inputs + 1] = record
    end
    return {
      get = function()
        if live() then
          return read()
        end
        return ""
      end,
      set = function(_, newText)
        if live() then
          box:SetText(FText(tostring(newText)))
          if record then
            -- A change made by the mod itself is not reported to onChange.
            local ok, current = pcall(read)
            record.last = ok and current or record.last
          end
        end
      end,
    }
  end

  -- A horizontal row on the page itself: text, item tiles and buttons side by side.
  function page.row()
    if not pageAlive() then
      return inertPageRow
    end
    local hbox = ui.construct(CLASS.hbox, ctx.tree)
    ctx.root:AddChildToVerticalBox(hbox)
    return makeRow(hbox, nil, true)
  end

  -- A scrolling list of rows (ScrollBox, HorizontalBox rows and the Fill slot are verified in game).
  function page.list()
    if not pageAlive() then
      return {
        clear = function() end,
        row = function()
          return inertRow
        end,
      }
    end
    local scroll = ui.construct(CLASS.scroll, ctx.tree)
    local slot = ctx.root:AddChildToVerticalBox(scroll)
    fillSlot(slot, "list")
    local generation = 0
    local live = liveCheck(scroll, "list")
    local list = {}

    function list.clear()
      if live() then
        scroll:ClearChildren()
        generation = generation + 1 -- rows made before this point are dead
      end
    end

    function list.row()
      if not live() then
        return inertRow
      end
      local hbox = ui.construct(CLASS.hbox, ctx.tree)
      scroll:AddChild(hbox)
      local born = generation
      local function sameGeneration()
        return born == generation
      end
      return makeRow(hbox, sameGeneration, false)
    end

    return list
  end

  -- A grid of clickable item tiles that wraps like rows of text and scrolls (WrapBox in a ScrollBox, verified in
  -- game for 48 tiles). WrapBox:ClearChildren is not verified: a failure is logged and the old tiles stay.
  function page.grid()
    if not pageAlive() then
      return {
        clear = function() end,
        tile = function() end,
      }
    end
    local scroll = ui.construct(CLASS.scroll, ctx.tree)
    local slot = ctx.root:AddChildToVerticalBox(scroll)
    fillSlot(slot, "grid")
    local wrap = ui.construct(CLASS.wrap, ctx.tree)
    scroll:AddChild(wrap)
    local generation = 0
    local addresses = {} -- clickable tiles of the current generation
    local live = liveCheck(scroll, "grid")
    local grid = {}

    function grid.clear()
      if not live() then
        return
      end
      local ok, problem = pcall(function()
        wrap:ClearChildren()
      end)
      if not ok then
        ctx.log(
          string.format("mod %s: grid:clear failed, the old tiles stay (unverified call): %s", ctx.owner, problem)
        )
        return
      end
      generation = generation + 1 -- tiles made before this point are dead
      for _, address in ipairs(addresses) do
        ctx.clicks:forget(address)
      end
      addresses = {}
    end

    -- spec (optional): { onClick = function(name) }. The tile count is not shown in the TAB menu, so there is none.
    function grid.tile(_, name, spec)
      if not live() then
        return
      end
      if type(name) ~= "string" or name == "" then
        error('grid:tile needs the item name as text, like "GentianNectar"', 2)
      end
      if spec ~= nil and (type(spec) ~= "table" or (spec.onClick ~= nil and type(spec.onClick) ~= "function")) then
        error("grid:tile takes an optional table { onClick = function(name) end }", 2)
      end
      local library = StaticFindObject(CLASS.library)
      local class = ui.findClass(CLASS.recipeTile, ctx.log)
      if not isValid(library) or not class then
        error("the item tile class of the game was not found")
      end
      local tile = library:Create(ctx.panel, class, ui.playerController())
      if not isValid(tile) then
        error("the game did not create an item tile")
      end
      tile:UpdateItemInfo(FName(name), 1, 0.0, 0.0, true, false, false)
      wrap:AddChildToWrapBox(tile)
      local onClick = spec and spec.onClick
      if onClick then
        local born = generation
        local address = registerClick(tile, function()
          return born == generation
        end, function()
          onClick(name)
        end)
        if address then
          addresses[#addresses + 1] = address
        end
      end
      -- The click hook of the tile class can only be registered once the class is loaded: now it is.
      if ctx.onTileCreated then
        local okHook, hookProblem = pcall(ctx.onTileCreated, class)
        if not okHook then
          ctx.log("could not prepare the tile click hook: " .. tostring(hookProblem))
        end
      end
    end

    return grid
  end

  return page, session
end

return ui
