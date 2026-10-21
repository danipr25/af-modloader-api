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
- From the UE4SS source (not tested in game): several handlers registered under one name all run, and only the last one's result counts. So the API registers each name once and dispatches itself.

## How AF Mod Loader API uses this

- The API turns the console on only when a mod other than the API added a command, and only if the player has not opted out with `{ "console": false }` in the file `af-modloader-api.json` in the `mods\.data` folder of the game. It decides once, at the first `ClientRestart` or the first `InitGameState`, when every mod has registered its commands, and checks again at each one until the console exists. Not verified in game yet.
- Each command name is registered once with `RegisterConsoleCommandGlobalHandler`, plus once more for its all-uppercase form, which only answers "Commands are lowercase: type <name>". As a precaution (not a verified fact), the callback compares the first word of the line with its own name before answering.
- Command names are lowercase `<namespace>.<name>` with a namespace of at least 3 characters, which avoids the short prefixes of the engine's console variables (pick a namespace from your mod name). `af.` is reserved for the API. Details in [api.md](api.md).

## Credits and license

The console is turned on the way UE4SS's `ConsoleEnablerMod` does it. That mod is part of UE4SS (https://github.com/UE4SS-RE/RE-UE4SS) and is MIT licensed:

```
MIT License

Copyright (c) 2022 Narknon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The notice above is the text of the `LICENSE` file shipped with UE4SS 3.0.1; it is also in the header of `mod/scripts/console.lua`.

## Seeing the output

Pressing the console key once opens a one-line bar that shows what you type but not the answers. Pressing it twice opens the full console, where command output (`outputDevice:Log`) appears. Verified in game 2026-10-21 with the API's `af.help` and the template's `mymod.hello`.
