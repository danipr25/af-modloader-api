-- Page widgets: the handles a mod's build(page) function uses, so mods never touch UMG directly.
-- Game-facing, tested in game. Every call here comes from docs/tab-menu.md or the in-game spike, except those
-- marked "unverified": each of those is wrapped in pcall and falls back to a clear log line.
local ui = {}

local CLASS = {
  vbox = "/Script/UMG.VerticalBox",
  hbox = "/Script/UMG.HorizontalBox", -- unverified class path (standard UMG)
  scroll = "/Script/UMG.ScrollBox", -- unverified class path (standard UMG)
  text = "/Script/UMG.TextBlock",
  edit = "/Script/UMG.EditableTextBox",
  tile = "/Game/Blueprints/WBP/Utility/WBP_SimpleItemTile.WBP_SimpleItemTile_C",
  library = "/Script/UMG.Default__WidgetBlueprintLibrary",
}
ui.FILL = 1 -- ESlateSizeRule::Fill; unverified

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

-- Creates a widget of a UMG class (verified for VerticalBox, TextBlock and EditableTextBox).
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
--        owner = mod id for logs, log = function(text) }
-- Returns the page handle for the mod and a session table: session.alive turns false when the page is rebuilt, and
-- session.inputs lists the inputs whose changes must be polled ({ read, last, onChange }).
function ui.newPage(ctx)
  local session = { alive = true, inputs = {} }

  -- Returns live(): true while the handle may be used. The first misuse is logged once, then ignored silently.
  local function liveCheck(widget, what, extraCheck)
    local warned = false
    return function()
      if session.alive and (extraCheck == nil or extraCheck()) and isValid(widget) then
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

  local inertRow = {
    text = function()
      return { set = function() end }
    end,
    item = function() end,
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

  -- A scrolling list of rows. Unverified: ScrollBox, HorizontalBox rows and the Fill slot.
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
    local okFill = pcall(function()
      slot:SetSize({ Value = 1.0, SizeRule = ui.FILL })
    end)
    if not okFill then
      ctx.log("the list could not be set to fill the page (unverified slot call): a long list may not scroll")
    end
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
      local rowLive = liveCheck(hbox, "row", sameGeneration)
      local row = {}
      function row.text(_, str)
        if not rowLive() then
          return { set = function() end }
        end
        return makeText(str, function(widget)
          hbox:AddChildToHorizontalBox(widget)
        end, sameGeneration)
      end
      function row.item(_, name, count)
        if rowLive() then
          makeItem(hbox, name, count, sameGeneration)
        end
      end
      return row
    end

    return list
  end

  return page, session
end

return ui
