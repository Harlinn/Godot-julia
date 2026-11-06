---
name: gdjl-13-debugging
description: "Phase 13: debugging and diagnostics for Julia scripts — external debugger attach, script debugger stack frames, exception reporting, output redirection."
agent: agent
---
Make Julia scripts debuggable at least as well as C# scripts. Follow the [project instructions](../copilot-instructions.md). Behavioral references: `csharp_script.cpp` (`debug_get_current_stack_info`, `debug_break`, `get_current_thread_name`, unhandled exception reporting), `GodotSharp/Core/DebuggingUtils.cs`, `ExceptionUtils` in `NativeInterop`, `GodotTools/Ides/` debugger launch helpers, and docs on C# debugging.

## Requirements

1. **Exception reporting**: every error from Julia (script callbacks, signal handlers, tasks, deferred calls) is reported via `print_script_error` with the deepest `res://` frame as source location, function name, and full Julia backtrace in the message. Map absolute paths back to `res://` paths. Shown in the Debugger → Errors tab with clickable source like C#.
2. **Script debugger integration**: implement `_debug_get_current_stack_info`, `_debug_get_error`, `_debug_get_stack_level_count/line/function/source/instance`, `_debug_get_stack_level_locals/members`, `_debug_get_globals` (best effort from backtraces / `Base.StackTraces`), so the Godot debugger's stack panel shows Julia frames when an error breaks.
3. **External debugger** (C# attach parity):
   - VS Code: support the Julia extension's debug adapter attached to the embedded runtime (e.g. connecting via the extension's external-REPL/debug server mechanism, or `DebugAdapter.jl` listening on a port set by `julia/debugger/port`). Generate `.vscode/launch.json` that launches/attaches to the running game.
   - CLI: `Debugger.jl`/`Infiltrator.jl` breakpoints usable when the game is started from a terminal.
   - Option `julia/debugger/wait_for_attach` to pause startup until a debugger connects.
   - Document the setup and any limitations (e.g. compiled-mode stepping) in `docs/debugging.md`.
4. **Output**: confirm stdout/stderr/logging redirection from phase 02 works in editor, running game, and exported debug builds; `print_rich` support via a `GD.print_rich` binding.
5. **Engine-call errors**: errors raised by engine methods called from Julia include the Julia call site.
6. **Optional, beyond C# parity**: profiler hooks (`_profiling_*`) — implement only if cheap; otherwise mark not required.

## Tests

- Integration: an exception in `_process` produces one Godot error per frame with correct `res://` file:line and the game keeps running.
- Stack info API returns Julia frames for a forced error.
- Manual test checklist for VS Code attach recorded in `docs/debugging.md`.

Update parity rows 9.1–9.5.
