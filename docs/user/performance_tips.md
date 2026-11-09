# Performance tips

Julia compiles each method for the argument types it is called with, so fast code is mostly code whose types the compiler can predict. Measurements of the engine boundary are in [docs/perf.md](../perf.md).

## Type your script fields

Fields of a `@godot_class` are its storage. Concrete field types (`Float64`, `Vector2`, `Union{Nothing, Node2D}`) let the compiler generate direct code. An untyped field is `Any`, which forces dynamic dispatch on every use.

```julia
using Godot

@godot_class mutable struct Mover <: Node2D
    speed::Float64 = 200.0       # good: concrete
    target::Vector2 = Vector2_ZERO
    scratch::Any = nothing       # avoid in hot code: every use is dynamic
end

function Godot._process(self::Mover, delta::Float64)
    step = Float32(self.speed * delta)
    self.position = move_toward(self.position, self.target, step)
end
```

```julia
m = Mover()
m.target = Vector2(10, 0)
Godot._process(m, 0.01)
@test m.position == Vector2(2, 0)
free(m)
```

## Avoid allocations in `_process`

Per-frame code runs thousands of times. Builtin math types (`Vector2`, `Transform3D`, ...) are stack values, so math on them does not allocate. Allocating a new array, string or closure every frame does. Reuse buffers stored in fields, and check with `@allocated`:

```julia
function sum_x(points::Vector{Vector2})
    s = 0.0f0
    for p in points
        s += p.x
    end
    return s
end
pts = [Vector2(i, 0) for i in 1:100]
sum_x(pts)                              # compile first
@test (@allocated sum_x(pts)) == 0
```

## Cache nodes and keep engine calls out of inner loops

Each engine call crosses into C++ (tens of nanoseconds for simple calls, about 1 µs when the engine calls a script method). Look nodes up once in `_ready` and store them in typed fields instead of calling `get_node` every frame. Do bulk work in Julia arrays and hand results to the engine once, for example as a packed array.

## Startup

- In the editor, the `Godot` package loads from its precompiled image in about a second.
- Exported games use a system image with your scripts compiled in (`julia/export/mode = sysimage`), which brings Julia startup to about 0.7 s. See [export](julia_export.md).
- Packages you `using` add their own load time. Keep the project environment lean.

## Threads

Heavy computations (pathfinding, procedural generation) can run on Julia threads (`julia/runtime/threads`) or `WorkerThreadPool` tasks. Post the results to the main thread with `Godot.post`. See [async](julia_async.md).

## Profiling

C# code is profiled with external tools (dotTrace, Visual Studio). Julia's sampling profiler, the `Profile` standard library, runs inside the game: profile a piece of script code and print the report to the Output panel. In a running game you can do the same from the debug REPL ([debugging](julia_debugging.md)), or save the samples and open them with ProfileView.jl or PProf.jl in your own Julia session.

```julia
using Profile

function busy(n)
    s = 0.0
    for i in 1:n
        s += sqrt(i)
    end
    return s
end
busy(10)                                # compile first
Profile.clear()
total = Ref(0.0)                        # use the results, or the compiler removes the work being profiled
@profile for _ in 1:200
    total[] += busy(100_000)
end
report = sprint(io -> Profile.print(IOContext(io, :displaysize => (24, 200)); format = :flat, maxdepth = 10))
@test occursin("busy", report)
```

`@time` and `@allocated` give quick numbers for a single call; [docs/perf.md](../perf.md) lists measured costs of the engine boundary.
