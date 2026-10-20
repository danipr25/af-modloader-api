-- Runs every check: formatting, lint and tests. Usage: lua scripts/check.lua [--fix]
-- With --fix, formatting is applied instead of only checked.
local fix = arg[1] == "--fix"

local steps = {
  { name = "format", command = fix and "stylua ." or "stylua --check ." },
  { name = "lint", command = "luacheck ." },
  { name = "tests", command = "lua tests/run.lua" },
}

local failed = {}
for _, step in ipairs(steps) do
  print(string.format("== %s: %s", step.name, step.command))
  if not os.execute(step.command) then
    failed[#failed + 1] = step.name
  end
end

if #failed > 0 then
  print("Failed: " .. table.concat(failed, ", "))
  os.exit(1)
end
print("All checks passed.")
