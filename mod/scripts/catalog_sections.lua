-- Sections on the V menu's item sheet (api.catalog.section). Game-facing, tested in game only in a probe: the
-- mechanism comes from docs/catalog-menu.md (verified in game 1.1.5024, 2026-10-22, in a probe that built one
-- section and updated its text on every item).
--
-- The item sheet (WBP_CatalogContent_C) is shown for the Materials and Goods tabs, each with its own instance. After
-- the game's UpdateContent runs for an item (ConfigName.ConfigName is its row name), every mod's section for that
-- sheet is rebuilt: one VerticalBox per mod per sheet, appended to the parent of Vtb_UsedIn (under "Used in
-- Crafting", above the records), cleared and filled again by the mod's build function. Clearing and rebuilding
-- inside the post hook is UNVERIFIED (the probe built once and then only changed a text).
local clicks = require("clicks")
local hooks = require("hooks")
local registry = require("registry")
local ui = require("ui")

local CONTENT_CLASS = "/Game/Blueprints/WBP/CatalogPanel/WBP_CatalogContent.WBP_CatalogContent_C"
local UPDATE_HOOK = CONTENT_CLASS .. ":UpdateContent"

local isValid = ui.isValid
local addressOf = ui.addressOf
local catalogSections = {}
local Sections = {}
Sections.__index = Sections

local function paramValue(param)
  local ok, value = pcall(function()
    return param:get()
  end)
  return ok and value or param
end

-- options: { registry = registry object, log = function(text) }
function catalogSections.new(options)
  local self = setmetatable({}, Sections)
  self.registry = options.registry
  self.log = options.log
  self.clicks = clicks.new(options.log) -- routes clicks on the buttons of the sections
  self.sheets = {} -- sheet address -> { sheet, parent, parentAddress, boxes = { [section key] = { root, session } } }
  self.hook = "none" -- "none", "requested" (handed to hooks.install) or "off"
  self.busy = false
  self.failed = {} -- section key -> true once its build failure was logged in full
  return self
end

-- Registers the UpdateContent hook when a mod added a section and the item sheet class is loaded (hooks.install
-- retries for a while when it is not). Called every time the V menu opens, and when its panel first appears.
function Sections:ensureHook()
  if self.hook ~= "none" or #self.registry:sections() == 0 then
    return
  end
  self.hook = "requested" -- before the deferral, so it is never registered twice
  -- Deferred to the game thread, out of the hook (usually BP_OnActivated) that called this.
  ExecuteInGameThread(function()
    hooks.install({
      {
        path = UPDATE_HOOK,
        effect = "Sections added by mods will not appear on the item sheet of the V menu.",
        onGiveUp = function()
          self.hook = "none" -- tried again the next time the V menu opens
        end,
        fn = function(context)
          local ok, problem = pcall(self.update, self, paramValue(context))
          if not ok then
            self.log("could not update the item sheet sections: " .. tostring(problem))
          end
        end,
      },
    }, self.log)
  end)
end

-- A click on a game button: calls the callback of the section button at that address, if there is one.
function Sections:route(address)
  self.clicks:route(address, true)
end

-- What a mod's build function receives: text, spaces, dividers and rows with text and buttons, nothing else.
local function sectionHandle(page)
  local section = {}
  section.text = page.text
  section.space = page.space
  section.divider = page.divider
  function section.row()
    local row = page:row()
    return registry.readonly({ text = row.text, button = row.button }, "a section row")
  end
  return registry.readonly(section, "a section")
end

local function itemOf(sheet)
  local ok, name = pcall(function()
    return sheet.ConfigName.ConfigName:ToString()
  end)
  if ok and type(name) == "string" and name ~= "" and name ~= "None" then
    return name
  end
end

-- Forgets a sheet's record and the clicks of its sections.
function Sections:dropRecord(address)
  local rec = self.sheets[address]
  self.sheets[address] = nil
  for _, box in pairs(rec and rec.boxes or {}) do
    if box.session then
      box.session.alive = false
      self.clicks:dropSession(box.session)
    end
  end
end

-- The sheet's record, made on the first update. Returns nil and the reason when the sheet does not look as expected.
function Sections:recordFor(sheet)
  local address = addressOf(sheet)
  local rec = self.sheets[address]
  if rec and isValid(rec.sheet) and isValid(rec.tree) and isValid(rec.parent) then
    return rec
  end
  if rec then
    self:dropRecord(address) -- made again below
  end
  local ok, parent = pcall(function()
    return sheet.Vtb_UsedIn:GetParent()
  end)
  if not ok or not isValid(parent) then
    return nil, "the item sheet has no Vtb_UsedIn with a parent"
  end
  local okTree, tree = pcall(function()
    return sheet.WidgetTree
  end)
  if not okTree or not isValid(tree) then
    return nil, "the item sheet has no WidgetTree"
  end
  rec = { sheet = sheet, tree = tree, parent = parent, parentAddress = addressOf(parent), boxes = {} }
  self.sheets[address] = rec
  return rec
end

-- The mod's box on this sheet: reused while it is valid and still under the sheet's parent, otherwise made again.
function Sections:boxFor(rec, entry)
  local box = rec.boxes[entry.key]
  if box and isValid(box.root) then
    local ok, same = pcall(function()
      local parent = box.root:GetParent() -- unverified
      return isValid(parent) and addressOf(parent) == rec.parentAddress
    end)
    if ok and same then
      return box
    end
  end
  if box and box.session then
    box.session.alive = false
    self.clicks:dropSession(box.session)
  end
  local root = ui.construct(ui.CLASS.vbox, rec.tree)
  rec.parent:AddChildToVerticalBox(root)
  box = { root = root }
  rec.boxes[entry.key] = box
  return box
end

function Sections:build(rec, entry, item)
  local box = self:boxFor(rec, entry)
  if box.session then
    box.session.alive = false
    self.clicks:dropSession(box.session)
    box.session = nil
  end
  pcall(function()
    box.root:ClearChildren()
  end)
  local ctx = {
    panel = rec.sheet,
    tree = rec.tree,
    root = box.root,
    owner = entry.owner,
    log = self.log,
    clicks = self.clicks,
    kind = "section",
  }
  local page, session = ui.newPage(ctx)
  box.session = session
  local ok, problem = xpcall(entry.build, debug.traceback, sectionHandle(page), item)
  if not ok then
    session.alive = false
    self.clicks:dropSession(session)
    pcall(function()
      box.root:ClearChildren()
    end)
    if not self.failed[entry.key] then
      self.failed[entry.key] = true
      self.log(
        string.format(
          'mod %s: the section "%s" failed to build for %s: %s',
          entry.owner,
          entry.id,
          item,
          tostring(problem)
        )
      )
    else
      self.log(
        string.format(
          'mod %s: the section "%s" failed to build for %s again (see the first error)',
          entry.owner,
          entry.id,
          item
        )
      )
    end
  end
end

-- UpdateContent has run for 'sheet': rebuilds every section on it for the item it now shows.
function Sections:update(sheet)
  if self.busy or not isValid(sheet) then
    return
  end
  local list = self.registry:sections()
  if #list == 0 then
    return
  end
  local item = itemOf(sheet)
  if not item then
    return
  end
  self.busy = true
  local ok, problem = pcall(function()
    for address, rec in pairs(self.sheets) do
      if not isValid(rec.sheet) then
        self:dropRecord(address)
      end
    end
    local rec, reason = self:recordFor(sheet)
    if not rec then
      if not self.loggedStructure then
        self.loggedStructure = true
        self.log(
          "AF item sheet sections are off for this sheet: "
            .. reason
            .. ". Mods that add sections will not show them. The game was not changed."
        )
      end
      return
    end
    for _, entry in ipairs(list) do
      local okEntry, entryProblem = pcall(self.build, self, rec, entry, item)
      if not okEntry then
        self.log(
          string.format('mod %s: could not make the section "%s": %s', entry.owner, entry.id, tostring(entryProblem))
        )
      end
    end
  end)
  self.busy = false
  if not ok then
    self.log("could not update the item sheet sections: " .. tostring(problem))
  end
end

return catalogSections
