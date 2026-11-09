# 16. Debugging: Parity Where Possible, Honesty Where Not

Debugging is where a scripting language earns your trust.

Think about what happens when a C# script throws in `_process`:

- Godot shows a script error at the right file and line.
- Clicking it opens the code, and the game keeps running.
- If the debugger is attached, the game pauses. Godot's Debugger panel shows the C# stack frames and local variables.
- If you want more, you attach Visual Studio, Rider or VS Code to the running game and step through it line by line.

Julia can match the first two of those almost exactly. It cannot match the third.

There is no out-of-process debugger that can attach to an embedded Julia runtime. And Julia's interactive debuggers need a terminal that Godot doesn't provide.

So this chapter covers a few lessons:

- how a prompt can demand parity and still welcome an honest "not possible",
- how to bound optional work,
- why manual checklists matter for what automation can't reach,
- why good error messages pay off twice when an agent is doing the work.

This phase builds on two earlier pieces. The script bridge (chapter 11) carries the `_debug_*` virtuals. The scheduler (chapter 13) has a per-frame pump that also serves the debug server.

## The Prompt

[`.github/prompts/gdjl-13-debugging.prompt.md`](../../.github/prompts/gdjl-13-debugging.prompt.md):

```markdown
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
```

## Anatomy of the Prompt

### "At Least as Well as C#", with an Escape Hatch Built In

The opening sentence sets a high bar: *"Make Julia scripts debuggable at least as well as C# scripts."*

Then requirement 3 admits, in its last bullet, that the bar may not be reachable everywhere: *"Document the setup and any limitations (e.g. compiled-mode stepping)."*

The example in parentheses is the important part. When we wrote the prompt, we suspected that stepping through compiled Julia code inside Godot might not work. So we asked in advance for that outcome to be **documented**, not hidden or faked.

A prompt that demands parity without allowing for limits invites one of two bad outcomes:

- the agent spends a session chasing the impossible, or
- it reports success on something that only half works.

Name the likely limit and ask for it to be documented. Then "here's what works, here's what can't, here's the workaround" becomes a successful result.

### Exhaustive Where It Matters

Requirement 2 lists every `_debug_*` virtual by name. It's the same technique you saw in chapter 11.

Without the list, an agent would likely implement the one or two hooks needed to make *something* appear in the Debugger panel. With it, frames, lines, functions, sources, locals, members and globals all get implemented, each with a C# reference.

### Mapping Paths Back to `res://`

Requirement 1 contains a small but critical instruction: *"Map absolute paths back to `res://` paths."*

Here's why it matters. Godot's Errors tab can only open a file that it recognizes as part of the project. A Julia backtrace naturally contains whatever path Julia recorded when the code was loaded.

The prompt anticipated that the two wouldn't match and made the translation explicit. What it didn't anticipate was *how* badly they would mismatch on Windows. We'll get to that.

### Bounding Optional Work

> **Optional, beyond C# parity**: profiler hooks (`_profiling_*`) — implement only if cheap; otherwise mark not required.

This is a technique for managing agent ambition.

Profiler integration is attractive and could absorb a lot of work. It is also outside the parity goal. So the prompt handles it in one line:

- it mentions profiling, so the agent doesn't wonder whether it was forgotten;
- it sets a budget: *"only if cheap"*;
- it defines the exit: *"otherwise mark not required"*.

The agent chose the exit. `docs/debugging.md` tells you what to use instead: *"use Julia's `Profile` in the debug REPL."*

### A Manual Checklist as a Deliverable

The last test bullet is not a test: *"Manual test checklist for VS Code attach recorded in `docs/debugging.md`."*

Some things can't run in a headless CI job, such as an IDE attaching to a game. An agent can't click through VS Code. It *can* write precise steps for a person to follow.

Making the checklist a **deliverable** keeps the gap between "automated" and "verified" visible.

## What the Agent Built

[ADR 0013](../adr/0013-debugging.md) records the design. [`docs/debugging.md`](../debugging.md) explains it to you as a game developer. The code lives in [`runtime/debugging.jl`](../../julia/Godot/src/runtime/debugging.jl) and [`runtime/debugserver.jl`](../../julia/Godot/src/runtime/debugserver.jl).

### Julia Errors as Godot Script Errors

The native ABI gained one more entry, bumping it to v5: `report_script_error`. It calls Godot's `print_script_error_with_message`.

Every unhandled Julia exception is reported at the **innermost user frame** in a `res://` file. That covers errors from:

- a virtual method,
- a signal handler,
- a Godot task,
- a posted job,
- property access.

The error's first line becomes the description. The full Julia stack trace becomes the message, with script paths shown as `res://`. And the game keeps running.

Deciding what counts as a "user frame" is a small piece of design. `user_frames` keeps frames from scripts, project files and user packages. It skips Base, standard libraries and the Godot package itself.

So an error inside `Godot.get_node` points at the *script line that called it*, not at the binding code.

### Julia Frames in Godot's Own Backtraces

Requirement 5 asks for engine errors raised during Julia calls to show the Julia call site.

Godot calls `_debug_get_current_stack_info` on every script language whenever it reports an error. Implement that virtual, and Julia frames appear in *every* engine error raised under Julia code.

The documentation's example: `get_node(self, "Missing")` reports `Node not found` with your `res://` call site.

There's a bonus side effect. `Engine.capture_script_backtraces()` and custom `Logger` subclasses now see Julia frames under the language name `Julia`.

One subtlety is worth knowing. While Julia is *reporting* its own error, Godot asks for the current stack. At that moment, the current stack is the reporting code, not the code that failed.

The fix stores the error's backtrace in task-local storage for the duration of the report (`:gdjl_pending_bt`), with a guard against recursion.

### Godot's Debugger Panel

When a debugger is attached, `report_unhandled` and the new `Godot.@breakpoint` macro call `EngineDebugger.script_debug(JuliaLanguage)` on the main thread.

A **`DebugState`** captures:

- the error,
- the frames,
- the frame-0 locals (via `Base.@locals`),
- the instance.

The `_debug_*` virtuals answer from it. Expressions you type in the Debugger panel are evaluated with the locals bound in the script module.

With `julia/debugger/break_on_error` (default on), an unhandled Julia error pauses the game in the panel, just as with C#.

### A Debug REPL Server Instead of Attach

Here is the honest part. ADR 0013's context paragraph states the constraint:

> Julia has no out-of-process debugger that can attach to an embedded runtime. Debugger.jl and Infiltrator.jl interpret code or open a nested REPL, and both need a terminal.

The prompt suggested attaching the VS Code Julia extension's debug adapter to the embedded runtime. Instead, the agent built what *is* possible: a **debug REPL server**.

Here's how it works:

- Debug builds of a game, with `julia/debugger/port` or `GDJL_DEBUG_PORT` set, listen on localhost.
- Requests are evaluated on the main thread between frames, so they can use the scene tree safely.
- A small client, [`addons/godot_julia/tools/godot_repl.jl`](../../addons/godot_julia/tools/godot_repl.jl), connects to it.
- `Godot.@breakpoint` without Godot's debugger runs a session on the connected client until `continue`.
- The option `julia/debugger/wait_for_attach` from requirement 3 blocks startup until a client connects.
- When VS Code is the external editor, opening a script writes a `tasks.json` entry (run the game with the server) and a `launch.json` configuration (start the REPL client).

That last point puts the whole workflow one keypress away.

### The Server Is an Execution Endpoint

A REPL server that evaluates arbitrary code is, by definition, a **remote code execution endpoint**. The agent treated it as one. From the ADR's consequences:

> The REPL server is an execution endpoint. It is therefore limited to debug builds and 127.0.0.1, and it is off unless a port is configured.

The code in [`debugserver.jl`](../../julia/Godot/src/runtime/debugserver.jl) enforces all three conditions:

- it listens on `Sockets.IPv4("127.0.0.1")`;
- it refuses to start in the editor or in non-debug builds (`Godot.is_debug_build(Godot.OS)`);
- it only starts when a port is set.

The documentation for game developers repeats the warning: *"Don't ship a release with debug templates and a port set."*

Security was not in the prompt. The agent added it because the feature demanded it. That's exactly the judgment you want.

### The Limitations, Written Down

The ADR's decision list ends with:

> **No gutter breakpoints or stepping.** This is recorded as PARTIAL on parity row 9.1. `@breakpoint` plus the REPL is the supported workflow.

The guide in `docs/debugging.md` has a *Limitations* section:

- no gutter breakpoints or stepping,
- locals only for the breakpoint frame,
- no profiler integration.

The matrix row explains why in one sentence: *"line breakpoints with stepping in compiled Julia are not possible (Debugger.jl/Infiltrator need a TTY, ADR 0013)"*.

## Where Reality Pushed Back

### `res://` Becomes `.res:\` on Windows

Scripts are evaluated with their `res://` paths as file names. So backtraces should be easy to map back, right?

On Windows they weren't. The phase 13 report lists this under *Fixed along the way*:

> **Script paths on Windows.** Julia's backtraces show script paths as `.res:\X.jl`, so script frames were being treated as Julia's own frames and skipped. This also affected the old error-location code. They are now mapped back to `res://`.

The likely explanation: Julia's debug info treats `res://Player.jl` as a relative path. It normalizes it with Windows separators, producing `.res:\Player.jl`.

That string starts with a dot. And a leading dot is how the earlier error-location code recognized Base frames. So every script frame was silently filtered out.

`res_path` now recognizes both forms ([`debugging.jl`](../../julia/Godot/src/runtime/debugging.jl)):

```julia
"""
`res://` path of a source file inside the project, else the file itself. Scripts are evaluated with `res://` names,
which Julia's debug info returns as `.res:\\x.jl` on Windows.
"""
function res_path(file::AbstractString)
    f = normslash(file)
    m = match(r"^(?:\./?)?res:/+(.*)$", f)
    m === nothing || return "res://" * m.captures[1]
```

Two things stand out:

- The bug was already present in the earlier error-location code. It looked plausible because it still pointed *somewhere*.
- The agent found it only when this phase's tests asserted the *exact* file and line.

Path normalization across platforms is a recurring source of bugs, for agents and people alike. Tests that compare exact paths are the only reliable guard.

### Task Errors Should Pause Too

The report also notes: *"Errors in `godot_task`s and `Godot.post` jobs now also pause in the debugger."*

Phase 10 had made unhandled task errors print with a stack trace. This phase made them consistent with errors in engine callbacks.

Consistency between code paths is easy to lose when each path was built in a different phase. Watch for it.

### A Breakpoint in a Task Pauses Only the Task

Here's a design consequence, documented rather than hidden:

> **One behaviour to know:** a breakpoint inside a `godot_task` pauses only that task and frames keep running. A breakpoint inside an engine callback pauses the whole game.

A Godot task is cooperative (chapter 13). When it waits at a breakpoint, it yields, and the frame loop continues.

If you want a whole-game pause from task code, `Godot.post` the work so it runs in the frame callback.

The agent's memory notes record the rule. The integration test deliberately breaks inside a posted job to check that the game really stops.

### Two Rows Stay `PARTIAL`, and Say Why

The report's opening paragraph:

> I finished phase 13 (`gdjl-13-debugging`). All test suites pass, but parity rows 9.1 and 9.3 are only PARTIAL: they each need a manual check I couldn't run headlessly.

**Row 9.1** (attach an external debugger) is partial for two reasons:

- stepping isn't possible;
- nobody has run the VS Code checklist yet.

**Row 9.3** (Julia frames in the Debugger panel) is fully implemented and unit-tested. But an *interactive* session in the editor's panel is a manual check.

Both rows are still `PARTIAL` today, with those notes. As chapter 3 showed, the driver later recognized that these rows needed a person, not more code, and moved on to phase 14.

## Closing the Loop

### An Error per Frame, at the Exact Line

The integration project [`tests/integration/debugging/`](../../tests/integration/debugging) implements the prompt's first test literally. [`Faulty.jl`](../../tests/integration/debugging/Faulty.jl) throws in its first three frames:

```julia
function Godot._process(self::Faulty, delta::Float64)
    self.count >= 3 && return
    self.count += 1
    error("faulty frame $(self.count)")
end
```

[`DebugTest.jl`](../../tests/integration/debugging/DebugTest.jl) is tagged `# parity: 9.2, 9.3, 9.5`. It installs a GDScript `Logger` (`error_logger.gd`) to capture what Godot actually reports.

It then checks for exactly three script errors at `res://Faulty.jl:14`, along with:

- the errors typed as script errors,
- the message as description,
- the Julia stack trace in the body,
- Julia frames in the script backtrace,
- a game that is still running.

```julia
        check(length(errs) == 3, "three faulty-frame errors (got $(length(errs)))")
        check(all(e -> string(e["file"]) == "res://Faulty.jl" && Int(e["line"]) == 14 && Int(e["type"]) == ERROR_TYPE_SCRIPT,
                  errs), "errors are script errors at res://Faulty.jl:14: $(isempty(errs) ? "" : errs[1])")
```

The same test also checks that:

- an engine error (`get_node(self, "Missing")`) carries the Julia call site, using `@__LINE__()` so the expected line can't drift;
- `capture_script_backtraces` returns a Julia frame at the calling line;
- a task failure is reported at the right line.

### The REPL, End to End

Next, the test connects to the debug server (port 47123 in the project's settings) with a plain socket. It evaluates requests, including multi-line ones with captured output. Finally, it runs a breakpoint session from a client task.

It checks that:

- the game is frozen while the session is open (the frame counter doesn't move);
- the breakpoint's locals evaluate (`x * 10 + y` gives `45`);
- `continue` resumes.

```julia
            check(result[] == 5, "@breakpoint returns after continue")
            check(frozen, "the game is paused during the session")
            check(occursin("GDJL_BREAK paused here at res://DebugTest.jl:", note), "break notice: $note")
            check(r1 == "45", "evaluate with the breakpoint's locals: $r1")
```

[`expect_errors.txt`](../../tests/integration/debugging/expect_errors.txt) lists exactly the three errors the test provokes (`faulty frame`, `Node not found`, `task failure`). Any other error fails the run.

### What Remains Manual

The *Manual checklist (not automated)* in [`docs/debugging.md`](../debugging.md) covers the rest in five steps:

- open the project in VS Code,
- run the server task,
- start the REPL launch configuration,
- hit a hot-reloaded `@breakpoint`,
- check the Debugger panel in the Godot editor.

Until someone runs it, rows 9.1 and 9.3 stay `PARTIAL`.

Run the automated part yourself with:

```powershell
julia tests/integration/run.jl debugging
```

## Techniques to Reuse

- **Demand parity, name the likely limit.** "At least as well as C#" plus "document limitations (e.g. compiled-mode stepping)" makes an honest partial result a success.
- **Bound optional work with a budget and an exit.** "Implement only if cheap; otherwise mark not required."
- **Make manual checklists deliverables.** When automation can't reach something, have the agent write the steps. Keep the row `PARTIAL` until a person runs them.
- **Treat debug endpoints as attack surface.** Localhost only, debug builds only, off by default, and say so in the docs.
- **Assert exact paths and lines.** Approximate error locations hide path-normalization bugs. Exact assertions expose them.
- **Good error messages pay twice.** Precise `res://file:line` reports help you, and they make every later agent iteration faster (see also chapter 6's "error messages that name the fix").

## Try It Yourself

1. Introduce a deliberate exception into a demo script's `_process`, for example in `demos/dodge_the_creeps/Player.jl`. Run `julia demos/run.jl`. Then give the agent only the reported error. Ask it to locate and explain the fault, without telling it what you changed.
2. Set `GDJL_DEBUG_PORT=47100` and run a demo from a terminal. Connect with `julia addons/godot_julia/tools/godot_repl.jl 47100` and inspect the running scene tree. Add `Godot.@breakpoint` to a `_process` method, save, and watch the hot reload deliver the breakpoint.
3. Work through the manual checklist in `docs/debugging.md` yourself. If everything passes, you have the evidence needed to move rows 9.1 and 9.3 closer to `DONE`. Ask the agent which parts of 9.1 would still stay open.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 9.1 | Attach an external debugger | PARTIAL (debug REPL server, `@breakpoint` sessions with locals, VS Code task and launch config, all tested; stepping in compiled Julia not possible, ADR 0013; VS Code checklist not yet run) |
| 9.2 | Unhandled exceptions → Godot error with stack trace | DONE (script errors at the innermost `res://` frame, full Julia stack trace, break on error) |
| 9.3 | Script debugger stack frames in the Debugger panel | PARTIAL (all `_debug_*` virtuals implemented and tested; interactive panel session is a manual check) |
| 9.4 | Console output in the Output panel | DONE (stdout/stderr/logging redirected; verified in exported builds in phase 14) |
| 9.5 | Errors from engine calls with source location | DONE (Julia frames in engine-error backtraces and `capture_script_backtraces`) |

---
[← Previous: Editor Integration](15-editor-integration.md) · [Contents](README.md) · [Next: Export →](17-export.md)
