# Debugging Julia scripts

Godot-julia reports Julia errors to Godot the same way C# does, shows Julia frames in Godot's backtraces and script debugger, and adds a debug REPL into the running game.

## Errors and stack traces

- An exception that escapes Julia code becomes a Godot **script error**. This covers virtual methods such as `_process`, signal handlers, `godot_task`s, `Godot.post` jobs and property access. The error is located at the innermost `res://` frame, for example `res://Player.jl:42`. Clicking it in the editor's Errors tab opens that line. The message holds the complete Julia stack trace, with script paths shown as `res://`. The game keeps running.
- Engine errors raised while Julia code is running carry the Julia frames ("Julia backtrace") in their script backtrace. For example, `get_node(self, "Missing")` reports `Node not found` with your `res://` call site.
- `Engine.capture_script_backtraces()` and `Logger` subclasses (`OS.add_logger`) see Julia frames under the language name `Julia`.

## Godot's script debugger

When the game runs from the editor (*Debug → Run* with the debugger attached):

- With `julia/debugger/break_on_error` (default `true`), an unhandled Julia error pauses the game in the **Debugger** panel. It shows the error, the Julia stack frames (file, line, function), the frame's locals, the script instance's members and the script module's globals. You can evaluate expressions there.
- `Godot.@breakpoint` (or `@breakpoint "message"`) pauses at that line with the local variables visible, like GDScript's `breakpoint`. *Continue* resumes. Without a debugger attached it does nothing.

Line breakpoints set in the editor gutter are not supported. Julia code is compiled, and the stepping debuggers (Debugger.jl, Infiltrator.jl) need a terminal, which Godot doesn't provide (ADR 0013). Use `@breakpoint` instead.

## Debug REPL server

Debug builds of a game (not the editor) start a localhost REPL server when one of these is set:

| Setting | Meaning |
|---|---|
| `julia/debugger/port` (project setting) or `GDJL_DEBUG_PORT` (environment) | Port on 127.0.0.1; 0 disables the server |
| `julia/debugger/wait_for_attach` or `GDJL_DEBUG_WAIT=1` | Block at startup until a client connects |
| `julia/debugger/break_on_error` | Pause in Godot's debugger on unhandled errors (default true) |

At startup the game prints `Godot-julia: Julia debug server listening on 127.0.0.1:<port>`. To connect:

```
julia addons/godot_julia/tools/godot_repl.jl 47100
godot> using Godot; get_frames_drawn(Godot.Engine)
```

- Requests run on the main thread between frames, so they can use the scene tree safely. Output from `println` is sent back to the client.
- When `Godot.@breakpoint` is hit and no Godot debugger is attached, the client shows `[breakpoint] ... locals: ...`. Expressions then see the breakpoint's local variables. `continue` (or `c`) resumes.
- A breakpoint inside an engine callback pauses the whole game. A breakpoint inside a `godot_task` pauses only that task.
- The server only listens on localhost and only in debug builds. Don't ship a release with debug templates and a port set.

Protocol, for other clients: each request is a single line, an `escape_string`-escaped Julia string that may contain several statements. Each reply is text followed by a line containing `GDJL_END`. A breakpoint notice is a reply whose first line starts with `GDJL_BREAK `.

## VS Code

When VS Code is the external editor (*Editor Settings → julia/editor/external_editor*), opening a script writes `.vscode/` files if they are missing:

- `settings.json`, which sets the Julia environment to the project;
- `tasks.json`, with the task **Godot: run game with Julia debug server** (sets `GDJL_DEBUG_PORT=47100`);
- `launch.json`, with the configuration **Godot: Julia debug REPL** (runs `godot_repl.jl 47100` with the Julia extension).

### Manual checklist (not automated)

1. Open the project folder in VS Code with the Julia extension installed.
2. Run the task *Godot: run game with Julia debug server*. The terminal shows the "listening" line.
3. Start *Godot: Julia debug REPL* (F5). In the REPL, `using Godot; get_frames_drawn(Godot.Engine)` returns a growing number.
4. Add `Godot.@breakpoint` to a `_process` method and save; it hot-reloads. The REPL shows `[breakpoint]`, the locals evaluate, and `continue` resumes.
5. In the Godot editor, run the game with the debugger. A thrown error stops in the Debugger panel with Julia frames and locals.

## Limitations

- No gutter breakpoints or stepping.
- Locals are shown for the breakpoint frame only. Outer frames show file, line and function.
- No profiler integration (`_profiling_*`); use Julia's `Profile` in the debug REPL.
