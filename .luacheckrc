-- Luacheck configuration. UE4SS runs Lua 5.4.
std = "lua54"
max_line_length = 120
-- .claude/ holds agent worktrees (other branches); luacheck does not read .gitignore.
exclude_files = { "tests/vendor/", ".claude/" }

-- Mods run inside the AF Mod Loader environment: AF and the UE4SS functions are globals they may read.
-- Calls the modules use that are not listed here are declared where they are used.
local mod_globals = {
  "AF",
  "FName",
  "FText",
  "FindFirstOf",
  "FindAllOf",
  "StaticFindObject",
  "LoadAsset",
  "StaticConstructObject",
  "RegisterHook",
  "RegisterConsoleCommandGlobalHandler",
  "ExecuteInGameThread",
  "ExecuteWithDelay",
  "LoopAsync",
  "LoopInGameThreadWithDelay",
  "CancelDelayedAction",
  "RegisterInitGameStatePostHook",
}
files["mod/"] = { read_globals = mod_globals }
files["template/"] = { read_globals = mod_globals }
