-- Packages the mod into a zip for a release. Usage (from the repository root): lua scripts/package.lua
-- The output goes to dist/. Releases are built by GitHub Actions, never from here.
local HELP = [[
Usage: lua scripts/package.lua

Run it from the repository root.

Builds dist\<id>-<version>.zip. The zip holds one folder, <id>\, with the contents of mod\. To install it, extract the
zip into <game>\mods. The id and the version are read from mod\mod.json.
Stops if dist\ already holds anything else than that zip, so a release never carries stray files. Delete dist\ first.]]

local SOURCE = "mod"
local DIST = "dist"
local STAGE = DIST .. "\\stage"
-- Windows' own tar (bsdtar) writes zip files. Git's tar, which is first on the PATH of many machines, cannot.
local TAR = "%SystemRoot%\\System32\\tar.exe"

local function fail(message)
  print("Error: " .. message)
  os.exit(1)
end

-- Runs a command. The tool name goes first and unquoted, or cmd.exe would mis-handle the quotes around the paths.
local function run(command, what)
  print("  " .. command)
  if os.execute(command) ~= true then
    fail(what .. " failed")
  end
end

local function dirExists(path)
  return os.execute('if exist "' .. path .. '\\" (exit 0) else (exit 1)') == true
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

local function listing(command)
  local lines = {}
  local pipe = assert(io.popen(command))
  for line in pipe:lines() do
    lines[#lines + 1] = (line:gsub("\r$", ""))
  end
  pipe:close()
  return lines
end

for _, argument in ipairs(arg) do
  if argument == "--help" or argument == "-h" then
    print(HELP)
    os.exit(0)
  else
    fail("unknown option " .. argument .. ". Run with --help to see the options")
  end
end

local manifest = readFile(SOURCE .. "/mod.json")
if not manifest then
  fail("run this from the repository root (" .. SOURCE .. "/mod.json was not found)")
end
local id = manifest:match('"id"%s*:%s*"([a-z0-9%-]+)"')
if not id then
  fail("could not find a valid id in " .. SOURCE .. "/mod.json")
end
local version = manifest:match('"version"%s*:%s*"(%d+%.%d+%.%d+)"')
if not version then
  fail("could not find a version like 1.2.3 in " .. SOURCE .. "/mod.json")
end

local zipName = id .. "-" .. version .. ".zip"
local zipPath = DIST .. "\\" .. zipName
print("Packaging " .. id .. " " .. version)

if dirExists(DIST) then
  for _, name in ipairs(listing('dir /b "' .. DIST .. '"')) do
    if name ~= zipName then
      fail(DIST .. "\\ already holds " .. name .. ". Delete the " .. DIST .. " folder and run this again")
    end
  end
end

run('xcopy "' .. SOURCE .. '" "' .. STAGE .. "\\" .. id .. '" /E /I /Y /Q', "copying " .. SOURCE)
os.remove(zipPath)
run(TAR .. ' -a -c -f "' .. zipPath .. '" -C "' .. STAGE .. '" "' .. id .. '"', "creating the zip")
run('rmdir /S /Q "' .. STAGE .. '"', "removing the staging folder")

-- The zip must hold <id>/mod.json, or the mod would not load after extracting it into <game>\mods.
local found = false
for _, entry in ipairs(listing(TAR .. ' -tf "' .. zipPath .. '"')) do
  if entry == id .. "/mod.json" then
    found = true
  end
end
if not found then
  fail(zipPath .. " does not hold " .. id .. "/mod.json")
end
print("Done: " .. zipPath)
os.execute('certutil -hashfile "' .. zipPath .. '" SHA256')
