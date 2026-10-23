-- Developer tool: copies the API mod from this repository into a game that already has AF Mod Loader, so it can be
-- tested without a release. Never shipped. It runs on the developer's machine, so it may use os.execute.
-- Usage (from the repository root): lua scripts/dev-install.lua [game folder] [--with-template] [--remove-template]
--   [--force]
local HELP = [[
Usage: lua scripts/dev-install.lua [game folder] [--with-template] [--remove-template] [--force]

Run it from the repository root, with the game closed.

  game folder        Alchemy Factory install folder. Default: the AF_GAME_DIR environment variable, then
                     C:\Program Files (x86)\Steam\steamapps\common\Alchemy Factory
  --with-template    Also copy the template mod (template/my-mod) into <game>\mods\my-mod
  --remove-template  Remove <game>\mods\my-mod (and nothing else), then stop
  --force            Replace or remove a my-mod folder whose scripts/main.lua differs from template/my-mod
                     (it may hold your own edits). A folder whose mod.json id is not the expected one is never touched.

It replaces <game>\mods\af-modloader-api with the contents of mod/. UE4SS and AF Mod Loader must already be
installed (the loader's own scripts/dev-install.lua does that). It does not touch any other mod.]]

local STEAM_DEFAULT = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Alchemy Factory"
local GAME_EXES = { "AlchemyFactory-Win64-Shipping.exe", "AlchemyFactory.exe" }
local API_SOURCE = "mod"
local API_FOLDER = "af-modloader-api"
local TEMPLATE_SOURCE = "template\\my-mod"
local TEMPLATE_FOLDER = "my-mod"
local TEMPLATE_MAIN = TEMPLATE_SOURCE .. "\\scripts\\main.lua"

local function fail(message)
  print("Error: " .. message)
  os.exit(1)
end

local function say(message)
  print(message)
end

-- Runs a command. The tool name goes first and unquoted, or cmd.exe would mis-handle the quotes around the paths.
local function run(command, what)
  say("  " .. command)
  local ok = os.execute(command)
  if ok ~= true then
    fail(what .. " failed")
  end
end

local function dirExists(path)
  return os.execute('if exist "' .. path .. '\\" (exit 0) else (exit 1)') == true
end

local function fileExists(path)
  local file = io.open(path, "rb")
  if file then
    file:close()
  end
  return file ~= nil
end

local function isRunning(exe)
  local output = assert(io.popen('tasklist /FI "IMAGENAME eq ' .. exe .. '" /NH')):read("a")
  return output:lower():find(exe:lower(), 1, true) ~= nil
end

local function readFile(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read("a")
  file:close()
  return text
end

-- Refuses to delete a folder that is not the mod we expect: its mod.json id must match. For the template, also
-- refuses when scripts/main.lua differs from the repository copy (it may hold the developer's own work), unless
-- --force is given.
local function checkRemovable(modsDir, folder, expectedId, sourceMain, force)
  local target = modsDir .. "\\" .. folder
  if not dirExists(target) then
    return
  end
  local manifest = readFile(target .. "\\mod.json")
  local id = manifest and manifest:match('"id"%s*:%s*"([^"]+)"')
  if id ~= expectedId then
    fail(
      target .. " is not the " .. expectedId .. " mod (its mod.json id is " .. tostring(id) .. "), so it was left alone"
    )
  end
  if sourceMain and not force then
    if readFile(target .. "\\scripts\\main.lua") ~= readFile(sourceMain) then
      fail(
        target .. "\\scripts\\main.lua differs from " .. sourceMain .. ". Use --force to replace or remove it anyway"
      )
    end
  end
end

-- Removes <game>\mods\<folder> and checks that it is really gone (rmdir can fail half way and still report 0).
local function removeModFolder(modsDir, folder)
  local target = modsDir .. "\\" .. folder
  if not dirExists(target) then
    return
  end
  say("Removing " .. target)
  run('rmdir /S /Q "' .. target .. '"', "removing " .. folder)
  if dirExists(target) then
    fail("could not remove " .. target .. " (is a file in it open?)")
  end
end

local function copyModFolder(source, modsDir, folder)
  local target = modsDir .. "\\" .. folder
  say("Copying " .. source .. " to " .. target)
  run('xcopy "' .. source .. '" "' .. target .. '" /E /I /Y /Q', "copying " .. folder)
end

local gameDir, withTemplate, removeTemplate, force
for _, argument in ipairs(arg) do
  if argument == "--help" or argument == "-h" then
    print(HELP)
    os.exit(0)
  elseif argument == "--with-template" then
    withTemplate = true
  elseif argument == "--force" then
    force = true
  elseif argument == "--remove-template" then
    removeTemplate = true
  elseif argument:sub(1, 2) == "--" then
    fail("unknown option " .. argument .. ". Run with --help to see the options")
  elseif not gameDir then
    gameDir = argument
  else
    fail("only one game folder can be given")
  end
end
gameDir = (gameDir or os.getenv("AF_GAME_DIR") or STEAM_DEFAULT):gsub("/", "\\"):gsub("\\+$", "")

if not fileExists(API_SOURCE .. "\\mod.json") then
  fail("run this from the repository root (" .. API_SOURCE .. "\\mod.json was not found)")
end

say("Game folder: " .. gameDir)
for _, exe in ipairs(GAME_EXES) do
  if isRunning(exe) then
    fail(exe .. " is running. Close the game first")
  end
end

local modsDir = gameDir .. "\\mods"
assert(modsDir:lower():sub(-5) == "\\mods", "mods must go inside the game's mods folder")
if not dirExists(modsDir) then
  fail(modsDir .. " does not exist. Install AF Mod Loader first (scripts/dev-install.lua in af-modloader)")
end
local loaderDir = gameDir .. "\\AlchemyFactory\\Binaries\\Win64\\ue4ss\\Mods\\AFModLoader"
if not dirExists(loaderDir) then
  fail(
    "AF Mod Loader is not installed in " .. loaderDir .. ". Install it first (af-modloader: scripts/dev-install.lua)"
  )
end

if removeTemplate then
  checkRemovable(modsDir, TEMPLATE_FOLDER, "my-mod", TEMPLATE_MAIN, force)
  say("Removing the template mod from " .. modsDir)
  removeModFolder(modsDir, TEMPLATE_FOLDER)
  say("Done.")
  os.exit(0)
end

checkRemovable(modsDir, API_FOLDER, "af-modloader-api", nil, force)
if withTemplate then
  checkRemovable(modsDir, TEMPLATE_FOLDER, "my-mod", TEMPLATE_MAIN, force)
end
removeModFolder(modsDir, API_FOLDER)
copyModFolder(API_SOURCE, modsDir, API_FOLDER)

if withTemplate then
  say("Adding the template mod (a folder called " .. TEMPLATE_FOLDER .. " that is already there is replaced)")
  removeModFolder(modsDir, TEMPLATE_FOLDER)
  copyModFolder(TEMPLATE_SOURCE, modsDir, TEMPLATE_FOLDER)
end

say("Done. Start the game and look for '[af-modloader-api] AF Mod Loader API 0.1.2 loaded' in UE4SS.log.")
