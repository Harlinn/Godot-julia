# Async, tasks and threads

Counterpart of the async sections of Godot's C# docs (`async`/`await`, `ToSignal`, `GodotSynchronizationContext`). Julia has tasks instead of `async` methods. Godot-julia runs **Godot tasks** on the main thread and resumes them while Godot processes frames, so after waiting a task can safely use the scene tree.

## Godot tasks

`godot_task(f)` runs `f()` as a task on the main thread (C#: calling an `async` method). It runs at once until its first wait. `@async_godot expr` is shorthand for the same.

```julia
t = godot_task() do
    wait(next_frame(DOC_ROOT))            # resume on the next process frame
    wait(delay(DOC_ROOT, 0.05))           # C#: await ToSignal(GetTree().CreateTimer(0.05), "timeout")
    :done
end
@test fetch(t) === :done
```

From a script method, start the task and return. The engine expects a Variant-compatible result, so return `nothing` rather than the task (C#: an `async void` method):

```julia
using Godot

@godot_class mutable struct Announcer <: Node
    shown::Vector{String} = String[]
end

function announce(self::Announcer)
    godot_task() do
        push!(self.shown, "Get ready")
        wait(delay(self, 0.05))
        push!(self.shown, "Go!")
    end
    return nothing
end
```

```julia
a = Announcer()
add_child(DOC_ROOT, a)
announce(a)
@test a.shown == ["Get ready"]
wait(delay(DOC_ROOT, 0.2))
@test a.shown == ["Get ready", "Go!"]
free(a)
```

## Awaiting signals

`wait(to_signal(obj, :signal))` and `@await to_signal(obj, :signal)` return the signal arguments as a tuple (C#: `await ToSignal(obj, SignalName.X)`). If `obj` is freed while waiting, the task ends quietly, as a cancelled C# task would. `wait(signal)` works with `Signal` values too.

```julia
t = godot_task() do
    node = Node()
    add_user_signal(node, "result")
    godot_task(() -> (wait(next_frame(DOC_ROOT)); emit_signal(node, :result, 42)))
    args = @await to_signal(node, :result)
    free(node)
    args
end
@test fetch(t) == (42,)
```

## Errors in tasks

An exception that escapes a Godot task is reported as a Godot script error with the Julia stack trace (C#: unobserved task exceptions). `fetch(task)` rethrows it.

## Deferred calls

`call_deferred(f, args...)` runs a Julia function at idle time, and `call_deferred(obj, :method, args...)` defers an engine call (C#: `CallDeferred`):

```julia
ran = Ref(false)
call_deferred(() -> (ran[] = true; nothing))
@test !ran[]
wait(next_frame(DOC_ROOT))
@test ran[]
```

## Threads

Julia threads and Godot's `WorkerThreadPool` can do work off the main thread (set `julia/runtime/threads` above 1). The scene tree must only be touched from the main thread. Hand results back with `Godot.post(f)`, which runs `f` on the main thread at the start of the next frame (C#: `SynchronizationContext.Post`).

```julia
result = Ref(0)
id = add_task(WorkerThreadPool, () -> begin
    r = sum(1:1000)                                 # runs on a worker thread
    Godot.post(() -> (result[] = r; nothing))       # back to the main thread
    nothing
end)
wait_for_task_completion(WorkerThreadPool, id)
wait(next_frame(DOC_ROOT))
@test result[] == 500500
```

`Threads.@spawn` works the same way: compute on any thread, then `Godot.post` the result.
