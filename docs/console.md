# The in-game console

How console commands work in Alchemy Factory with UE4SS. Game 1.1.5023, UE4SS 1181, verified in game on 2026-10-20 with a throwaway Lua mod.

## Enabling the console

The shipping game has no console. A Lua mod can create one the way UE4SS's sample `ConsoleEnablerMod` does (MIT, UE4SS-RE): construct `/Script/Engine.Console` with the game viewport as outer, assign it to `GameViewport.ViewportConsole` when that is not valid, and add console keys to `/Script/Engine.Default__InputSettings` `ConsoleKeys`. Run it once at start in `ExecuteInGameThread` and again from a post hook on `/Script/Engine.PlayerController:ClientRestart`.

Verified: the console opens with `F10` and with the key left of `1` (`º` on a Spanish keyboard).

## Commands

- `RegisterConsoleCommandGlobalHandler(name, fn)` and `RegisterConsoleCommandHandler(name, fn)` both work. The callback gets `(fullCommand, parameters, outputDevice)` and must return `true` (handled) or `false`.
- Names with a dot work (`spike.ping`).
- Parameters exclude the command name; double quotes group words: `spike.ping a "b c"` gives 2 parameters.
- Names are case-sensitive: `SPIKE.PING` did not reach a handler registered as `spike.ping`.
- `outputDevice:Log(text)` writes to the in-game console; `print` only reaches `UE4SS.log`.
- In UE4SS, several handlers registered under one name all run and only the last one's result counts, so the API must register each name once and dispatch itself.
