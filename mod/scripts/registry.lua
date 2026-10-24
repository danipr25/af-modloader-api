-- Registry of the tabs, item sheet sections and console commands that mods declare. Pure Lua with no game access,
-- so it is tested without the game (tests/test_registry.lua). Mods reach it through the handle that use(AF) returns.
local registry = {}

local Registry = {}
Registry.__index = Registry

local NAMESPACE_MIN = 3
local NAME_MAX = 64
local TITLE_MAX = 40
local TAB_ID_MAX = 32
-- The menus a tab can go in: "tab" is the TAB menu (the default), "catalog" the V menu (the item catalog).
local MENUS = { tab = true, catalog = true }
-- The game panels a mod can put side tabs on (api.panels.tab).
local PANELS = { cauldron = true }
-- The side tab of the game's own content: a mod tab with this title (any case) could not be told apart from it.
local PANEL_RESERVED_TITLE = "cauldron"
-- Titles of the game's own tabs, per menu: a mod tab with one of these could not be told apart from the game's.
local GAME_TITLES = {
  tab = { Player = true, World = true, Recognition = true },
  catalog = { Materials = true, Goods = true, Stats = true, Ledger = true },
}

-- A table that raises an error when written to. It is not a security boundary: it stops accidental changes to the
-- shared API that every mod uses.
function registry.readonly(source, label)
  return setmetatable({}, {
    __index = source,
    __newindex = function(_, key)
      error(string.format("%s is read-only: cannot set '%s'", label or "this table", tostring(key)), 2)
    end,
    __metatable = false,
  })
end

-- Command names are lowercase "<namespace>.<name>". The namespace has at least three characters, which avoids the
-- short prefixes of the engine's own console variables (r., t., fx. ...); pick a namespace from your mod name.
-- "af." belongs to the API itself.
-- Returns nil when the name is fine, or the reason it is not.
function registry.commandNameProblem(name, owner, selfId)
  if type(name) ~= "string" or name == "" then
    return 'the command name must be text like "mymod.hello"'
  end
  if #name > NAME_MAX then
    return string.format("the command name '%s' is longer than %d characters", name, NAME_MAX)
  end
  if name:find("[^a-z0-9._-]") then
    return string.format(
      "the command name '%s' may only use lowercase letters, digits, '.', '_' and '-' (the console is case-sensitive)",
      name
    )
  end
  local namespace, rest = name:match("^([^.]+)%.(.+)$")
  if not namespace then
    return string.format("the command name '%s' must look like <namespace>.<name>, for example \"mymod.hello\"", name)
  end
  if rest:find("^%.") or rest:find("%.$") or rest:find("%.%.") then
    return string.format("the command name '%s' has an empty part between dots", name)
  end
  if namespace == "af" then
    if owner ~= selfId then
      return string.format("the namespace 'af.' is reserved for the API itself, so '%s' cannot use it", name)
    end
    return nil
  end
  if #namespace < NAMESPACE_MIN then
    return string.format(
      "the namespace of '%s' is too short: use at least %d characters before the first dot",
      name,
      NAMESPACE_MIN
    )
  end
  return nil
end

-- options: { selfId = the API's own mod id, version = text, log = function(text) }
function registry.new(options)
  local self = setmetatable({}, Registry)
  self.selfId = options.selfId
  self.version = options.version
  self.log = options.log
  self.sealed = false
  self.tabList = {} -- tab entries in registration order
  self.tabsByKey = {} -- "<mod id>/<tab id>" -> entry
  self.tabsByTitle = {} -- title -> entry (titles are unique across both menus)
  self.panelTabList = {} -- panel side tabs in registration order
  self.panelTabsByKey = {} -- "<mod id>/<tab id>" -> entry
  self.sectionList = {} -- item sheet sections in registration order
  self.sectionsByKey = {} -- "<mod id>/<section id>" -> entry
  self.commandList = {}
  self.commandsByName = {} -- registered lowercase name -> entry
  self.commandsByAlias = {} -- uppercase alias -> entry
  self.worldEnterList = {} -- { owner, fn } in registration order
  -- Optional callbacks, set by the game-facing modules:
  --   onCommandAdded(entry) registers the name with the console
  --   onTabRefresh(entry)   rebuilds the page of a tab
  --   onTabSelect(entry)    selects the tab in its menu; returns whether it was scheduled
  --   onPanelTabAdded(entry)   a panel side tab was registered
  --   onPanelTabRefresh(entry) rebuilds the page of a panel side tab
  --   runDeferred(owner, fn)   runs fn on the game thread later (api.defer)
  --   worldCurrent()        the current world (a fresh copy) or nil
  self.onCommandAdded = nil
  self.onTabRefresh = nil
  self.onTabSelect = nil
  self.onPanelTabAdded = nil
  self.onPanelTabRefresh = nil
  self.runDeferred = nil
  self.worldCurrent = nil
  return self
end

-- From now on tabs and commands can no longer be added. Called when the game starts running, which is after
-- every mod's entrypoint has finished.
function Registry:seal()
  self.sealed = true
end

function Registry:isSealed()
  return self.sealed
end

local function lateMessage(what)
  return string.format(
    "%s can only be called while your mod's entrypoint runs (at the top level of main.lua). "
      .. "The game has already started, so it is too late to add it now.",
    what
  )
end

-- Returns an entry, or nil plus the problem and its kind: "invalid" (a bug in the mod), "late" or "duplicate".
function Registry:addTab(owner, spec)
  if self.sealed then
    return nil, lateMessage("tabs.add"), "late"
  end
  if type(spec) ~= "table" then
    return nil,
      'tabs.add needs a table: { id = "recipes", title = "My Tab", build = function(page) ... end }',
      "invalid"
  end
  local menu = spec.menu
  if menu == nil then
    menu = "tab"
  elseif type(menu) ~= "string" or not MENUS[menu] then
    return nil,
      'tabs.add: \'menu\' must be "tab" (the TAB menu, the default) or "catalog" (the V menu), not ' .. tostring(menu),
      "invalid"
  end
  local id, title = spec.id, spec.title
  if type(id) ~= "string" or #id > TAB_ID_MAX or not id:find("^[a-z0-9][a-z0-9_-]*$") then
    return nil,
      "tabs.add: 'id' must be 1 to " .. TAB_ID_MAX .. " lowercase letters, digits, '-' or '_', like \"recipes\"",
      "invalid"
  end
  if type(title) ~= "string" or title:find("^%s*$") or #title > TITLE_MAX then
    return nil, "tabs.add: 'title' must be text of 1 to " .. TITLE_MAX .. " characters", "invalid"
  end
  if type(spec.build) ~= "function" then
    return nil, "tabs.add: 'build' must be a function(page) that fills the page", "invalid"
  end
  if GAME_TITLES[menu][title] then
    return nil,
      string.format('tabs.add: the title "%s" is used by the game\'s own tabs, choose another', title),
      "invalid"
  end
  local key = owner .. "/" .. id
  if self.tabsByKey[key] then
    return nil, string.format("mod %s already added a tab with id '%s'", owner, id), "duplicate"
  end
  local other = self.tabsByTitle[title]
  if other then
    -- The title is how the tab is found in the menu again, so two tabs cannot share it.
    return nil,
      string.format('mod %s cannot add a tab titled "%s": mod %s already uses that title', owner, title, other.owner),
      "duplicate"
  end
  local entry = { owner = owner, id = id, key = key, title = title, build = spec.build, menu = menu }
  local registryRef = self
  entry.handle = registry.readonly({
    refresh = function()
      if registryRef.onTabRefresh then
        registryRef.onTabRefresh(entry)
      end
    end,
    select = function()
      if registryRef.onTabSelect then
        return registryRef.onTabSelect(entry) == true
      end
      return false
    end,
  }, "a tab")
  self.tabList[#self.tabList + 1] = entry
  self.tabsByKey[key] = entry
  self.tabsByTitle[title] = entry
  return entry
end

-- Side tabs of a game panel (api.panels.tab). Returns an entry, or nil plus the problem and its kind (like addTab).
function Registry:addPanelTab(owner, spec)
  if self.sealed then
    return nil, lateMessage("panels.tab"), "late"
  end
  if type(spec) ~= "table" then
    return nil,
      'panels.tab needs a table: { id = "recipes", title = "Recipes", build = function(page, info) ... end }',
      "invalid"
  end
  local panel = spec.panel
  if panel == nil then
    panel = "cauldron"
  elseif type(panel) ~= "string" or not PANELS[panel] then
    return nil, "panels.tab: 'panel' must be \"cauldron\" (the default), not " .. tostring(panel), "invalid"
  end
  local id, title = spec.id, spec.title
  if type(id) ~= "string" or #id > TAB_ID_MAX or not id:find("^[a-z0-9][a-z0-9_-]*$") then
    return nil,
      "panels.tab: 'id' must be 1 to " .. TAB_ID_MAX .. " lowercase letters, digits, '-' or '_', like \"recipes\"",
      "invalid"
  end
  if type(title) ~= "string" or title:find("^%s*$") or #title > TITLE_MAX then
    return nil, "panels.tab: 'title' must be text of 1 to " .. TITLE_MAX .. " characters", "invalid"
  end
  if type(spec.build) ~= "function" then
    return nil, "panels.tab: 'build' must be a function(page, info) that fills the page", "invalid"
  end
  if title:gsub("^%s+", ""):gsub("%s+$", ""):lower() == PANEL_RESERVED_TITLE then
    return nil,
      string.format('panels.tab: the title "%s" is the game\'s own tab of that panel, choose another', title),
      "invalid"
  end
  local key = owner .. "/" .. id
  if self.panelTabsByKey[key] then
    return nil, string.format("mod %s already added a panel tab with id '%s'", owner, id), "duplicate"
  end
  for _, other in ipairs(self.panelTabList) do
    if other.panel == panel and other.title == title then
      -- The title is the tab's label on the panel, so two tabs of one panel cannot share it.
      return nil,
        string.format(
          'mod %s cannot add a panel tab titled "%s": mod %s already uses that title',
          owner,
          title,
          other.owner
        ),
        "duplicate"
    end
  end
  local entry = { owner = owner, id = id, key = key, title = title, build = spec.build, panel = panel }
  local registryRef = self
  entry.handle = registry.readonly({
    refresh = function()
      if registryRef.onPanelTabRefresh then
        registryRef.onPanelTabRefresh(entry)
      end
    end,
  }, "a panel tab")
  self.panelTabList[#self.panelTabList + 1] = entry
  self.panelTabsByKey[key] = entry
  if self.onPanelTabAdded then
    self.onPanelTabAdded(entry)
  end
  return entry
end

-- Item sheet sections of the V menu. Returns an entry, or nil plus the problem and its kind (like addTab).
function Registry:addSection(owner, spec)
  if self.sealed then
    return nil, lateMessage("catalog.section"), "late"
  end
  if type(spec) ~= "table" then
    return nil,
      'catalog.section needs a table: { id = "cauldron", build = function(section, itemName) ... end }',
      "invalid"
  end
  local id = spec.id
  if type(id) ~= "string" or #id > TAB_ID_MAX or not id:find("^[a-z0-9][a-z0-9_-]*$") then
    return nil,
      "catalog.section: 'id' must be 1 to " .. TAB_ID_MAX .. " lowercase letters, digits, '-' or '_', like \"info\"",
      "invalid"
  end
  if type(spec.build) ~= "function" then
    return nil, "catalog.section: 'build' must be a function(section, itemName) that fills the section", "invalid"
  end
  local key = owner .. "/" .. id
  if self.sectionsByKey[key] then
    return nil, string.format("mod %s already added a section with id '%s'", owner, id), "duplicate"
  end
  local entry = { owner = owner, id = id, key = key, build = spec.build }
  self.sectionList[#self.sectionList + 1] = entry
  self.sectionsByKey[key] = entry
  return entry
end

function Registry:addCommand(owner, spec)
  if self.sealed then
    return nil, lateMessage("console.add"), "late"
  end
  if type(spec) ~= "table" then
    return nil,
      'console.add needs a table: { name = "mymod.hello", help = "...", run = function(args, out) ... end }',
      "invalid"
  end
  local problem = registry.commandNameProblem(spec.name, owner, self.selfId)
  if problem then
    return nil, "console.add: " .. problem, "invalid"
  end
  if type(spec.help) ~= "string" or spec.help:find("^%s*$") then
    return nil, "console.add: 'help' must be a one-line description, af.help shows it to the player", "invalid"
  end
  if type(spec.run) ~= "function" then
    return nil, "console.add: 'run' must be a function(args, out)", "invalid"
  end
  local name = spec.name
  local alias = name:upper()
  local taken = self.commandsByName[name] or self.commandsByAlias[name]
  if taken then
    return nil,
      string.format("mod %s cannot add the command '%s': mod %s already registered it", owner, name, taken.owner),
      "duplicate"
  end
  local entry = { owner = owner, name = name, alias = alias ~= name and alias or nil, help = spec.help, run = spec.run }
  self.commandList[#self.commandList + 1] = entry
  self.commandsByName[name] = entry
  if entry.alias then
    self.commandsByAlias[entry.alias] = entry
  end
  if self.onCommandAdded then
    self.onCommandAdded(entry)
  end
  return entry
end

-- The typed name -> entry, and true when it was the all-uppercase alias.
function Registry:findCommand(typed)
  local entry = self.commandsByName[typed]
  if entry then
    return entry, false
  end
  entry = self.commandsByAlias[typed]
  if entry then
    return entry, true
  end
  return nil
end

-- The tabs in registration order. With 'menu' ("tab" or "catalog"), only the tabs of that menu.
function Registry:tabs(menu)
  if menu == nil then
    return { table.unpack(self.tabList) }
  end
  local list = {}
  for _, entry in ipairs(self.tabList) do
    if entry.menu == menu then
      list[#list + 1] = entry
    end
  end
  return list
end

-- The side tabs of one panel ("cauldron") in registration order.
function Registry:panelTabs(panel)
  local list = {}
  for _, entry in ipairs(self.panelTabList) do
    if entry.panel == panel then
      list[#list + 1] = entry
    end
  end
  return list
end

function Registry:sections()
  return { table.unpack(self.sectionList) }
end

-- Commands sorted by name.
function Registry:commands()
  local list = { table.unpack(self.commandList) }
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return list
end

-- The sorted ids of the mods (other than the API itself) that registered a console command. The console is only
-- enabled when this is not empty: af.help alone is no reason to open the developer console.
function Registry:consoleNeededBy()
  local seen, owners = {}, {}
  for _, entry in ipairs(self.commandList) do
    if entry.owner ~= self.selfId and not seen[entry.owner] then
      seen[entry.owner] = true
      owners[#owners + 1] = entry.owner
    end
  end
  table.sort(owners)
  return owners
end

-- Returns true, or nil plus the problem and its kind: "invalid" (a bug in the mod) or "late".
function Registry:addWorldEnter(owner, fn)
  if self.sealed then
    return nil, lateMessage("world.onEnter"), "late"
  end
  if type(fn) ~= "function" then
    return nil, "world.onEnter needs a function(world) that runs when a world is loaded", "invalid"
  end
  self.worldEnterList[#self.worldEnterList + 1] = { owner = owner, fn = fn }
  return true
end

-- The onEnter callbacks in registration order.
function Registry:worldCallbacks()
  return { table.unpack(self.worldEnterList) }
end

-- The per-mod handle: what a mod calls. 'AF' is the mod's own AF table, and only identifies the owner in logs.
function Registry:use(AF)
  if type(AF) ~= "table" or type(AF.modId) ~= "string" or type(AF.log) ~= "function" then
    error(
      "af-modloader-api: use() needs your mod's AF table. Write: "
        .. 'local api = AF.require("af-modloader-api").use(AF)',
      2
    )
  end
  local owner = AF.modId
  local registryRef = self
  local inertTab = registry.readonly({
    refresh = function() end,
    select = function()
      return false
    end,
  }, "a tab")

  local tabs = {}
  function tabs.add(spec)
    local entry, problem, kind = registryRef:addTab(owner, spec)
    if entry then
      return entry.handle
    end
    if kind == "duplicate" then
      -- Refused, but the mod keeps running: it gets a tab that does nothing.
      registryRef.log(string.format("%s: tab refused: %s", owner, problem))
      return inertTab
    end
    error(problem, 2)
  end

  local inertPanelTab = registry.readonly({
    refresh = function() end,
  }, "a panel tab")
  local panels = {}
  function panels.tab(spec)
    local entry, problem, kind = registryRef:addPanelTab(owner, spec)
    if entry then
      return entry.handle
    end
    if kind == "duplicate" then
      registryRef.log(string.format("%s: panel tab refused: %s", owner, problem))
      return inertPanelTab
    end
    error(problem, 2)
  end

  local catalog = {}
  function catalog.section(spec)
    local entry, problem, kind = registryRef:addSection(owner, spec)
    if entry then
      return true
    end
    if kind == "duplicate" then
      registryRef.log(string.format("%s: section refused: %s", owner, problem))
      return false
    end
    error(problem, 2)
  end

  local console = {}
  function console.add(spec)
    local entry, problem, kind = registryRef:addCommand(owner, spec)
    if entry then
      return true
    end
    if kind == "duplicate" then
      registryRef.log(string.format("%s: command refused: %s", owner, problem))
      return false
    end
    error(problem, 2)
  end

  local world = {}
  function world.onEnter(fn)
    local ok, problem = registryRef:addWorldEnter(owner, fn)
    if not ok then
      error(problem, 2)
    end
  end
  function world.current()
    if registryRef.worldCurrent then
      return registryRef.worldCurrent()
    end
    return nil
  end

  -- Runs fn on the game thread soon, never inside the caller. An error in fn is logged with the mod id.
  local function defer(fn)
    if type(fn) ~= "function" then
      error("api.defer needs a function: api.defer(function() ... end)", 2)
    end
    -- Without the game module (only in tests, main.lua always sets runDeferred) the function runs at once.
    if registryRef.runDeferred then
      registryRef.runDeferred(owner, fn)
      return
    end
    local ok, problem = xpcall(fn, debug.traceback)
    if not ok then
      registryRef.log(string.format("mod %s: a deferred function failed: %s", owner, tostring(problem)))
    end
  end

  return registry.readonly({
    version = self.version,
    defer = defer,
    world = registry.readonly(world, "api.world"),
    tabs = registry.readonly(tabs, "api.tabs"),
    panels = registry.readonly(panels, "api.panels"),
    catalog = registry.readonly(catalog, "api.catalog"),
    console = registry.readonly(console, "api.console"),
  }, "the API handle")
end

return registry
