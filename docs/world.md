# Which world is loaded

What the API's `api.world` relies on. Game 1.1.5023, UE4SS 1181, verified in game on 2026-10-21 with a throwaway probe mod (it logged the fields below at every `InitGameState`; the probe is not part of this repository).

The game keeps each playthrough as a "world" with several save slots (manual saves and autosaves). The loaded world is on the game instance subsystem `GameSaveLoadSubsystem`, found with `FindFirstOf("GameSaveLoadSubsystem")` (the API skips the class default object, whose name contains `Default__`).

## Verified

| Situation | What the `RegisterInitGameStatePostHook` callback sees |
|---|---|
| Game start, main menu | `IsPreviewScene = true`, `IsStartup = true`, `WorldTitleName` empty |
| Load a save | `IsPreviewScene = false`, `WorldTitleName` = the world's name plus a number (for example `Prueba_2609125624`), `ReloadedName` = the slot that was loaded (for example `AutoSave0`) |
| New game | `IsPreviewScene = false`, `IsReloaded = true`, `WorldTitleName` = `<name>_<number>` and `NewGameName` = `<name>`, already before the first save. There is no window with an empty title |
| New game right after another world | Its own new title, not the old world's |
| Back to the main menu | `IsPreviewScene = true`, and `WorldTitleName` still holds the last world's title. So the title alone does not say a world is loaded: `IsPreviewScene` decides |
| Load another slot of the same world | The same `WorldTitleName` |
| `NewGameName` after loading a world | Keeps the last new game's name, so it cannot tell worlds apart |

- `WorldTitleName` is UTF-8: a world named with `ñú` gave the bytes `C3 B1 C3 BA`, and the escaped key `~C3~B1~C3~BA_2610216118` opened, wrote and read back a file in `mods\.data`.
- `ExecuteWithDelay` followed by `ExecuteInGameThread` runs.
- `os.rename` onto an existing file fails ("File exists"); `os.remove` followed by `os.rename` works.

## How the API decides

At every `InitGameState` the current world is cleared and an internal counter is bumped. The world is entered when `IsPreviewScene` is `false` and `WorldTitleName` is not empty. Anything else (menu, empty title, a subsystem that cannot be read) means no world, with one log line. Each enter gets a new `generation` and logs one line: title, key, generation, and `NewGameName`, `IsSandbox` and `NetSession` (each read on its own, so a missing one does not hide the others).

After a UE4SS mods restart there is no `InitGameState` until the next load, so the API reads the subsystem once, about a second after it starts, and only enters (it never reports "no world" from that read). The read is skipped if a game state started in the meantime.

## Not verified

- The read after a UE4SS mods restart (Ctrl+R) inside a world: that it enters and the template then shows the title.
- Multiplayer: what `NetSession` holds and what a client sees. Only logged.
- Sandbox worlds: what `IsSandbox` and the title look like. Only logged.
- The order in which several mods' `InitGameState` hooks run, so whether another mod's own hook sees the old or the new world through `api.world.current()`. Hence the advice to put world work in `onEnter`.
- The API's own `onEnter`, `current()` and log lines in game (the facts above come from the probe, not from the API).
