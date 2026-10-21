-- Calls a function every few milliseconds on the game thread, and can stop it. Game-facing: tested in game.
-- UE4SS's own game-thread loop is used when this UE4SS build has it; otherwise a background loop whose only
-- job is to hand each tick to the game thread.
local loop = {}

-- Returns stop() (call it to end the loop) and the name of the UE4SS function used, or nil and a message when
-- no loop could be started.
function loop.start(intervalMs, tick, log)
  local stopped = false
  local function guarded()
    if stopped then
      return
    end
    local ok, problem = pcall(tick)
    if not ok then
      log("a timed task failed: " .. tostring(problem))
    end
  end

  if type(LoopInGameThreadWithDelay) == "function" and type(CancelDelayedAction) == "function" then
    local ok, handle = pcall(LoopInGameThreadWithDelay, intervalMs, guarded)
    if ok then
      return function()
        stopped = true
        pcall(CancelDelayedAction, handle)
      end,
        "LoopInGameThreadWithDelay"
    end
  end
  if type(LoopAsync) == "function" then
    local ok, problem = pcall(LoopAsync, intervalMs, function()
      if stopped then
        return true
      end
      ExecuteInGameThread(guarded)
      return false
    end)
    if ok then
      return function()
        stopped = true
      end, "LoopAsync"
    end
    return nil, tostring(problem)
  end
  return nil, "this UE4SS build has no timed loops"
end

return loop
