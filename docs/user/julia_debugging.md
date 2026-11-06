# Debugging

Errors in Julia scripts are reported as Godot script errors at the `res://` line that raised them, with the full Julia stack trace. Godot's *Debugger* panel shows the Julia stack frames and local variables. `Godot.@breakpoint` pauses at a line, and debug builds can open a REPL into the running game.

The complete guide is [docs/debugging.md](../debugging.md). In brief:

```julia
using Godot

@godot_class mutable struct Careful <: Node
    hp::Int = 3
end

function damage!(self::Careful, n::Int)
    self.hp -= n
    # Pauses in the editor's debugger (or a connected debug REPL); does nothing when no debugger is attached.
    self.hp < 0 && Godot.@breakpoint "hp went negative"
    return self.hp
end
```

```julia
c = Careful()
@test damage!(c, 5) == -2     # no debugger attached here: the breakpoint is skipped
free(c)
```

- **Unhandled errors** in callbacks, signal handlers and tasks are printed as `SCRIPT ERROR:` with the Julia stack trace. The game keeps running. With `julia/debugger/break_on_error`, a game started from the editor pauses in the Debugger panel.
- **Debug REPL**: set `julia/debugger/port` (or `GDJL_DEBUG_PORT`) and run `julia addons/godot_julia/tools/godot_repl.jl <port>` to evaluate Julia inside the running game.
- **Logging**: `println`, `@info`, `@warn` and `@error` go to Godot's Output panel. Warnings and errors are reported as Godot warnings and errors.
