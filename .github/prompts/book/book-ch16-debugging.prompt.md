---
name: book-ch16-debugging
description: "Book chapter 16: the logic behind gdjl-13-debugging — error reporting, script debugger stack frames, and external debugger attach for embedded Julia."
agent: agent
---
Write chapter 16 of the book, `docs/book/16-debugging.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-13-debugging](../gdjl-13-debugging.prompt.md).

## Focus

- **"At least as well as C#", with a fallback.** Where full parity is impossible (stepping in compiled Julia), the matrix records `PARTIAL` with an explanation and ADR 0013. Show how a prompt can demand parity while allowing honest partial results.
- **Optional work, explicitly bounded.** "Optional, beyond C# parity: profiler hooks — implement only if cheap; otherwise mark not required." A technique for bounding agent ambition.
- **Manual checklists for what automation cannot reach.** The VS Code attach checklist in [`docs/debugging.md`](../../../docs/debugging.md). An agent can write the checklist, but a human must run it.
- **Debuggability of the AI's own output.** Good error messages (`res://` file:line, full backtrace) also make the agent's later iterations faster.

## Leads to Verify

- ABI v5 added `report_script_error`. `runtime/debugging.jl` and `debugserver.jl` implement the debug REPL server (`julia/debugger/port`/`GDJL_DEBUG_PORT`, `wait_for_attach`), `Godot.@breakpoint` sessions with locals, and a `godot_repl.jl` client.
- On Windows, stack frames of scripts loaded as `res://X.jl` show the file as `.res:\X.jl`, so the code always uses `res_path`. Platform path normalization is a recurring source of agent bugs. Do not mention any developer machine paths.
- `Logger.ERROR_TYPE_SCRIPT == 2`.
- Debugger.jl and Infiltrator need a TTY, which explains the limitation recorded in matrix row 9.1.

## Artifacts to Inspect

`julia/Godot/src/runtime/debugging.jl`, `debugserver.jl`, `docs/adr/0013-debugging.md`, `docs/debugging.md`, `docs/user/julia_debugging.md`, `tests/integration/debugging/`.

## Try It Yourself

Introduce a deliberate exception in a demo script's `_process`, run it headlessly, and ask the agent to locate the fault using only the reported error.

Parity rows: 9.1–9.5. Navigation: previous chapter 15, next chapter 17.
