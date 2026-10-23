-- Registers UE4SS hooks, retrying for a while in case the game class is not loaded yet. Game-facing: tested in game.
local hooks = {}

local MAX_ATTEMPTS = 60
local RETRY_MS = 5000

-- entries: list of { path = "<class path>:<function>", fn = callback, effect = "what does not work without it" }.
-- An entry may have onGiveUp(), called when its last attempt failed.
-- Tries at once; whatever fails is retried every few seconds, and a final log line says what never worked.
function hooks.install(entries, log)
  local function attempt(pending, number)
    local failed = {}
    for _, entry in ipairs(pending) do
      local ok, problem = pcall(RegisterHook, entry.path, entry.fn)
      if not ok then
        entry.problem = tostring(problem)
        failed[#failed + 1] = entry
      end
    end
    if #failed == 0 then
      return
    end
    if number == 1 then
      log(string.format("%d game hook(s) are not available yet, retrying every %d s", #failed, RETRY_MS // 1000))
    end
    if number >= MAX_ATTEMPTS then
      for _, entry in ipairs(failed) do
        log(string.format("could not hook %s (%s). %s", entry.path, entry.problem, entry.effect))
        if entry.onGiveUp then
          entry.onGiveUp()
        end
      end
      return
    end
    ExecuteWithDelay(RETRY_MS, function()
      ExecuteInGameThread(function()
        attempt(failed, number + 1)
      end)
    end)
  end
  attempt(entries, 1)
end

return hooks
