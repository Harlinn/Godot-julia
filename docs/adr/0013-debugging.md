# ADR 0013: Debugging

- Status: Accepted
- Date: 2026-11-06

## Context

C# reports unhandled exceptions as script errors with source locations (`CSharpLanguage::debug_get_current_stack_info`, `DebuggingUtils.cs`). It also shows managed frames in Godot's debugger, and IDEs attach a debugger to the .NET runtime through a debugging protocol. Julia has no out-of-process debugger that can attach to an embedded runtime. Debugger.jl and Infiltrator.jl interpret code or open a nested REPL, and both need a terminal. Godot's own script debugger, however, is open to any `ScriptLanguageExtension` through the `_debug_*` virtuals and `EngineDebugger.script_debug`.

## Decision

- **Script errors.** The host ABI goes to v5 and gains `report_script_error`, which calls `print_script_error_with_message`. `Runtime.report_exception` reports at the innermost `res://` frame. The description is the error's first line, and the message is the full Julia stack trace. On Windows, Julia's debug info turns `res://x.jl` into `.res:\x.jl`; `res_path` maps it back.
- **Backtraces.** `_debug_get_current_stack_info` returns the user frames, skipping Base, stdlibs and Godot.jl. Godot calls it for every error, so engine errors raised under Julia calls carry Julia frames. While a Julia error is being reported, the error's own backtrace is used (task-local `:gdjl_pending_bt`). A guard prevents recursion.
- **Godot's debugger.** Unhandled errors (`report_unhandled`) and `Godot.@breakpoint` call `EngineDebugger.script_debug(JuliaLanguage)` on the main thread when the debugger is active. A `DebugState` holds the error, frames, frame-0 locals (`Base.@locals`) and the instance. The `_debug_*` virtuals answer from it. Expressions are evaluated with the locals bound in the script module.
- **Debug REPL server instead of attach.** Debug builds of a game with `julia/debugger/port` or `GDJL_DEBUG_PORT` set listen on localhost. Requests are evaluated on the main thread once per frame. `@breakpoint` without a Godot debugger runs a session on the connected clients until `continue`. The client is `addons/godot_julia/tools/godot_repl.jl`. VS Code gets a generated task and launch configuration.
- **No gutter breakpoints or stepping.** This is recorded as PARTIAL on parity row 9.1. `@breakpoint` plus the REPL is the supported workflow.

## Consequences

- Error locations, backtraces and the Debugger panel behave as they do for C#. Attaching an IDE debugger with stepping remains a gap.
- The REPL server is an execution endpoint. It is therefore limited to debug builds and 127.0.0.1, and it is off unless a port is configured.
