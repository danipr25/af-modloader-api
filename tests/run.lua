-- Runs every tests/test_*.lua file with LuaUnit. Usage: lua tests/run.lua (from the repository root)
-- Each test file returns a table of test classes, for example { TestSmoke = { testSomething = function() end } }.
package.path = "./tests/vendor/?.lua;./tests/?.lua;" .. package.path

local lu = require("luaunit")

local function fileExists(path)
  local file = io.open(path, "r")
  if file then
    file:close()
  end
  return file ~= nil
end

-- Tracked and new (not ignored) files, so a new test runs before it is committed.
local list = assert(io.popen('git ls-files --cached --others --exclude-standard -- "tests/test_*.lua"'))
local suites = {}
for path in list:lines() do
  -- Only files directly in tests/ (pathspec * also matches subfolders), and skip ones deleted but not staged.
  local module = path:match("^tests/(test_[^/]+)%.lua$")
  if module and fileExists(path) then
    local classes = require(module)
    if type(classes) ~= "table" then
      error(path .. " must return a table of test classes, for example { TestThing = { ... } }", 0)
    end
    for name, class in pairs(classes) do
      suites[#suites + 1] = { name, class }
    end
  end
end
if not list:close() then
  print("Could not list test files with git. Run this from inside the repository.")
  os.exit(1)
end

table.sort(suites, function(a, b)
  return a[1] < b[1]
end)

if #suites == 0 then
  print("No tests found in tests/test_*.lua")
  os.exit(1)
end

local runner = lu.LuaUnit.new()
runner:runSuiteByInstances(suites)
os.exit(runner.result.notSuccessCount == 0 and 0 or 1)
