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
  scale = "/Script/UMG.ScaleBox",
  overlay = "/Script/UMG.Overlay",
  image = "/Script/UMG.Image",
  library = "/Script/UMG.Default__WidgetBlueprintLibrary",
}
ui.CLASS = CLASS
ui.FILL = 1 -- ESlateSizeRule::Fill
ui.ARROW_TEXTURE = "/Game/Arts/UI/Interaction/T_UI_RightArrow.T_UI_RightArrow"
ui.GOLD = { R = 1.0, G = 0.75, B = 0.2, A = 1.0 }
ui.GREY = { R = 0.45, G = 0.42, B = 0.38, A = 1.0 }
local GOLD, GREY = ui.GOLD, ui.GREY

-- Slot alignments, EStretch::UserSpecified, ESlateVisibility::HitTestInvisible (verified in game, 2026-10-22).
local H_LEFT, H_CENTER, V_CENTER = 1, 2, 2
local USER_SPECIFIED, HIT_TEST_INVISIBLE = 7, 3
-- Small widgets are drawn inside a ScaleBox: the text at 0.7, the buttons at 0.6. The arrow image is larger than
-- the button's art seems to need, because the scale shrinks it too (64 is a guess: the in-game test checks it).
local SMALL_TEXT_SCALE, SMALL_BUTTON_SCALE, ARROW_IMAGE_SIZE = 0.7, 0.6, 64.0

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

-- Finds a game class that may not be loaded at start: StaticFindObject, then LoadAsset. Logs once per class path
-- which way worked, or that it is not available. Returns the class, or nil.
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

-- Finds a game texture that may not be loaded yet: StaticFindObject, then LoadAsset, tried once per path (both
-- verified for the arrow texture). Logs once per path if it had to be loaded, or that it is not available.
-- Returns the texture, or nil.
local textureTried = {}
function ui.findTexture(path, log)
  local texture = StaticFindObject(path)
  if not isValid(texture) and not textureTried[path] and type(LoadAsset) == "function" then
    textureTried[path] = true
    pcall(LoadAsset, path)
    texture = StaticFindObject(path)
    log(
      isValid(texture) and ("game texture " .. path .. ": loaded with LoadAsset")
        or ("game texture " .. path .. " is not available: widgets that need it fall back or fail")
    )
  end
  if isValid(texture) then
    return texture
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

-- What a dead handle hands out: the same methods as a live one, doing nothing. Every dead path uses these, so a
-- mod that keeps a handle too long never gets nil or a missing method.
function ui.inertText()
  return {
    set = function() end,
    color = function() end,
  }
end
local inertText = ui.inertText

function ui.inertButton()
  return {
    set = function() end,
    enable = function() end,
  }
end
local inertButton = ui.inertButton

function ui.inertArrow()
  return {
    enable = function() end,
  }
end
local inertArrow = ui.inertArrow

-- A ScaleBox that draws its child at a fixed scale but keeps the child's real layout size (verified in game).
local arrowFallbackWarned = false
local function scaleBox(tree, scale)
  local box = ui.construct(CLASS.scale, tree)
  box:SetStretch(USER_SPECIFIED)
  box:SetUserSpecifiedScale(scale)
  return box
end

-- Checks one color channel (a number) and clamps it to 0-1.
local function channel(value, name)
  if type(value) ~= "number" or value ~= value then
    error(string.format("text:color needs numbers from 0 to 1, but %s is %s", name, tostring(value)), 3)
  end
  return math.max(0.0, math.min(1.0, value)) + 0.0
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

  -- Centers a child of a row vertically, so a text, a tile and a button side by side share a middle line
  -- (HorizontalBoxSlot, verified in game). Logged once per page if the game refuses.
  local centerWarned = false
  local function centerSlot(slot)
    local ok, problem = pcall(function()
      slot:SetVerticalAlignment(V_CENTER)
    end)
    if not ok and not centerWarned then
      centerWarned = true
      ctx.log(
        string.format(
          "mod %s: a row child could not be centered, it sits at the top of its row: %s",
          ctx.owner,
          tostring(problem)
        )
      )
    end
  end

  -- Checks the optional table of page:text (wrapAllowed) or row:text and returns wrap and small. The errors point
  -- at the mod's call (level 3).
  local function textOptions(opts, fn, wrapAllowed)
    local usage = wrapAllowed and '{ wrap = true or false, size = "normal" or "small" }'
      or '{ size = "normal" or "small" }'
    if opts == nil then
      return nil, false
    end
    local bad = type(opts) ~= "table"
    if not bad then
      bad = (opts.wrap ~= nil and (not wrapAllowed or type(opts.wrap) ~= "boolean"))
        or (opts.size ~= nil and opts.size ~= "normal" and opts.size ~= "small")
    end
    if bad then
      error(string.format("%s takes an optional table %s", fn, usage), 3)
    end
    local small = opts.size == "small"
    if small and opts.wrap then
      error(string.format("%s: size = 'small' cannot be combined with wrap", fn), 3)
    end
    return opts.wrap, small
  end

  -- add(widget, small) puts the finished widget on its page or row (a small text arrives inside its ScaleBox).
  local function makeText(str, add, extraCheck, wrap, small)
    local widget = ui.construct(CLASS.text, ctx.tree)
    widget:SetText(FText(tostring(str)))
    if wrap then
      local ok, problem = pcall(function()
        widget:SetAutoWrapText(true)
      end)
      if not ok then
        ctx.log(
          string.format(
            "mod %s: a text could not be set to wrap, a long line may run past the panel: %s",
            ctx.owner,
            tostring(problem)
          )
        )
      end
    end
    if small then
      local box = scaleBox(ctx.tree, SMALL_TEXT_SCALE)
      box:AddChild(widget)
      add(box, true)
    else
      add(widget, false)
    end
    local live = liveCheck(widget, "text", extraCheck)
    return {
      set = function(_, newText)
        if live() then
          widget:SetText(FText(tostring(newText)))
        end
      end,
      -- r, g, b, a from 0 to 1 (a defaults to 1). The API builds the game's color struct itself.
      color = function(_, r, g, b, a)
        local red, green, blue = channel(r, "red"), channel(g, "green"), channel(b, "blue")
        local alpha = 1.0
        if a ~= nil then
          alpha = channel(a, "alpha")
        end
        if live() then
          local ok, problem = pcall(function()
            local color = { R = red, G = green, B = blue, A = alpha }
            widget:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
          end)
          if not ok then
            ctx.log(string.format("mod %s: a text color could not be set: %s", ctx.owner, tostring(problem)))
          end
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
    centerSlot(hbox:AddChildToHorizontalBox(tile))
    return liveCheck(tile, "item tile", extraCheck)
  end

  -- Registers a click callback for a widget. The callback runs in the router's pcall, never inside the hook's.
  -- isDisabled (optional): function() -> true while the widget is disabled; its clicks are then not routed.
  local function registerClick(widget, extraCheck, fn, isDisabled)
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
      disabled = isDisabled,
      fn = fn,
    })
    return address
  end

  -- Creates the game's clickable recipe tile (the one the grid uses) for an item. The count is not shown in the
  -- TAB menu, so there is none. Returns the tile and its class.
  local function createRecipeTile(name)
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
    return tile, class
  end

  -- The click hook of the tile class can only be registered once the class is loaded: now it is.
  local function notifyTileCreated(class)
    if ctx.onTileCreated then
      local okHook, hookProblem = pcall(ctx.onTileCreated, class)
      if not okHook then
        ctx.log("could not prepare the tile click hook: " .. tostring(hookProblem))
      end
    end
  end

  -- Creates one of the game's buttons with its label (an empty label for the arrows).
  local function createButton(label)
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
    return button
  end

  -- small: the button is drawn inside a ScaleBox at 0.6.
  local function makeButton(hbox, label, onClick, extraCheck, small)
    if type(label) ~= "string" or label == "" then
      error('row:button needs the label as text, like "Next"', 3)
    end
    if type(onClick) ~= "function" then
      error("row:button needs a function: row:button(label, function() ... end)", 3)
    end
    local button = createButton(label)
    if small then
      local box = scaleBox(ctx.tree, SMALL_BUTTON_SCALE)
      box:AddChild(button)
      centerSlot(hbox:AddChildToHorizontalBox(box))
    else
      centerSlot(hbox:AddChildToHorizontalBox(button))
    end
    local enabled = true
    registerClick(button, extraCheck, onClick, function()
      return not enabled
    end)
    local live = liveCheck(button, "button", extraCheck)
    return {
      set = function(_, newLabel)
        if live() then
          button:SetButtonText(FText(tostring(newLabel)))
        end
      end,
      -- A disabled button is grey and ignores clicks (SetIsEnabled, verified in game). Call it after the button
      -- is in its row. The click router also skips a disabled button, in case the game still reports the click.
      enable = function(_, on)
        if type(on) ~= "boolean" then
          error("button:enable needs true or false", 2)
        end
        if not live() then
          return
        end
        local ok, problem = pcall(function()
          button:SetIsEnabled(on)
        end)
        if ok then
          enabled = on -- the routing flag changes only when the game accepted the change
        else
          ctx.log(
            string.format(
              "mod %s: a button could not be %s: %s (it stays as it was: %s)",
              ctx.owner,
              on and "enabled" or "disabled",
              tostring(problem),
              on and "it looks grey and its clicks are ignored" or "it looks enabled and its clicks work"
            )
          )
        end
      end,
    }
  end

  -- An arrow button: the game's button with no text in a small ScaleBox, the game's arrow picture on top (gold,
  -- mirrored for "previous", not hit-testable so the click lands on the button). Without the texture it is a small
  -- button labelled "<" or ">". The handle is { enable } on every path.
  local function makeArrow(hbox, direction, onClick, extraCheck)
    if direction ~= "previous" and direction ~= "next" then
      error('row:arrow needs "previous" or "next" as the direction', 3)
    end
    if type(onClick) ~= "function" then
      error('row:arrow needs a function: row:arrow("next", function() ... end)', 3)
    end
    local texture = ui.findTexture(ui.ARROW_TEXTURE, ctx.log)
    if texture == nil then
      if not arrowFallbackWarned then
        arrowFallbackWarned = true
        ctx.log(
          string.format(
            "mod %s: the arrow picture is not available, so arrows are small buttons labelled < and >",
            ctx.owner
          )
        )
      end
      local fallback = makeButton(hbox, direction == "next" and ">" or "<", onClick, extraCheck, true)
      return {
        enable = function(_, on)
          if type(on) ~= "boolean" then
            error("arrow:enable needs true or false", 2)
          end
          fallback:enable(on)
        end,
      }
    end
    local button = createButton("")
    local box = scaleBox(ctx.tree, SMALL_BUTTON_SCALE)
    local overlay = ui.construct(CLASS.overlay, ctx.tree)
    overlay:AddChildToOverlay(button)
    local image = ui.construct(CLASS.image, ctx.tree)
    image:SetBrushFromTexture(texture, false)
    image:SetDesiredSizeOverride({ X = ARROW_IMAGE_SIZE, Y = ARROW_IMAGE_SIZE })
    image:SetColorAndOpacity(GOLD)
    image:SetVisibility(HIT_TEST_INVISIBLE)
    if direction == "previous" then
      image:SetRenderScale({ X = -1.0, Y = 1.0 })
    end
    local inner = overlay:AddChildToOverlay(image)
    inner:SetHorizontalAlignment(H_CENTER)
    inner:SetVerticalAlignment(V_CENTER)
    box:AddChild(overlay)
    centerSlot(hbox:AddChildToHorizontalBox(box))
    local enabled = true
    registerClick(button, extraCheck, onClick, function()
      return not enabled
    end)
    local live = liveCheck(button, "arrow", extraCheck)
    return {
      -- Like button:enable: SetIsEnabled, and the picture is grey when off and gold when on.
      enable = function(_, on)
        if type(on) ~= "boolean" then
          error("arrow:enable needs true or false", 2)
        end
        if not live() then
          return
        end
        local ok, problem = pcall(function()
          button:SetIsEnabled(on)
        end)
        if not ok then
          ctx.log(
            string.format(
              "mod %s: an arrow could not be %s: %s",
              ctx.owner,
              on and "enabled" or "disabled",
              tostring(problem)
            )
          )
          return
        end
        enabled = on -- the routing flag changes only when the game accepted the change
        local okColor, colorProblem = pcall(function()
          image:SetColorAndOpacity(on and GOLD or GREY)
        end)
        if not okColor then
          ctx.log(string.format("mod %s: an arrow's color could not be set: %s", ctx.owner, tostring(colorProblem)))
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
    -- opts (optional): { size = "small" } shows the text at 0.7 of its size.
    function row.text(_, str, opts)
      if not rowLive() then
        return inertText()
      end
      local small = select(2, textOptions(opts, "row:text", false))
      return makeText(str, function(widget)
        centerSlot(hbox:AddChildToHorizontalBox(widget))
      end, extraCheck, nil, small)
    end
    -- opts (optional, page rows only): { onClick = function(name) } makes the tile clickable. It is then the recipe
    -- tile of the grid, which shows no count: count must be nil or 1.
    function row.item(_, name, count, opts)
      if not rowLive() then
        return
      end
      if opts ~= nil then
        if not withButtons then
          error("row:item: only rows of a page take options (a list row has no clickable tiles)", 2)
        end
        if type(opts) ~= "table" or (opts.onClick ~= nil and type(opts.onClick) ~= "function") then
          error("row:item takes an optional table { onClick = function(name) end }", 2)
        end
      end
      local onClick = opts and opts.onClick
      if onClick == nil then
        makeItem(hbox, name, count, extraCheck)
        return
      end
      if type(name) ~= "string" or name == "" then
        error('row:item needs the item name as text, like "GentianNectar"', 2)
      end
      if count ~= nil and count ~= 1 then
        error("row:item: a clickable tile shows no count, so the count must be nil or 1", 2)
      end
      local tile, class = createRecipeTile(name)
      centerSlot(hbox:AddChildToHorizontalBox(tile))
      registerClick(tile, extraCheck, function()
        onClick(name)
      end)
      notifyTileCreated(class)
    end
    if withButtons then
      -- opts (optional): { small = true } shows a smaller button (a ScaleBox at 0.6).
      function row.button(_, label, onClick, opts)
        if not rowLive() then
          return inertButton()
        end
        if opts ~= nil and (type(opts) ~= "table" or (opts.small ~= nil and type(opts.small) ~= "boolean")) then
          error("row:button takes an optional table { small = true or false }", 2)
        end
        local handle = makeButton(hbox, label, onClick, extraCheck, opts and opts.small)
        return handle -- not a tail call: a tail call would drop the mod's frame from the error level
      end
      -- direction is "previous" or "next".
      function row.arrow(_, direction, onClick)
        if not rowLive() then
          return inertArrow()
        end
        local handle = makeArrow(hbox, direction, onClick, extraCheck)
        return handle -- not a tail call: a tail call would drop the mod's frame from the error level
      end
    end
    return row
  end

  -- What a dead page or list hands out: the same methods as a live row, doing nothing.
  local inertRow = {
    text = inertText,
    item = function() end,
  }
  local inertPageRow = {
    text = inertText,
    item = inertRow.item,
    button = inertButton,
    arrow = inertArrow,
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

  -- opts (optional): { wrap = true } makes a long line wrap at the panel's edge instead of running past it.
  -- { size = "small" } shows the text at 0.7 of its size, left-aligned (it cannot be combined with wrap).
  function page.text(_, str, opts)
    if not pageAlive() then
      return inertText()
    end
    local wrap, small = textOptions(opts, "page:text", true)
    return makeText(str, function(widget, isSmall)
      local slot = ctx.root:AddChildToVerticalBox(widget)
      if isSmall then
        -- A ScaleBox in a vertical box is centered by default: left-align it (unverified call).
        local ok, problem = pcall(function()
          slot:SetHorizontalAlignment(H_LEFT)
        end)
        if not ok then
          ctx.log(
            string.format(
              "mod %s: a small text could not be left-aligned (unverified call), it may sit in the middle: %s",
              ctx.owner,
              tostring(problem)
            )
          )
        end
      end
    end, nil, wrap, small)
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
      local tile, class = createRecipeTile(name)
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
      notifyTileCreated(class)
    end

    return grid
  end

  return page, session
end

return ui
