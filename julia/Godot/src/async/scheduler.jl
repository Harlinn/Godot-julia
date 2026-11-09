# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Main-thread scheduling of Julia tasks: GodotSynchronizationContext / GodotTaskScheduler parity.
# Ported from GodotSharp/Core/GodotSynchronizationContext.cs and GodotTaskScheduler.cs (MIT, Godot contributors).
# Godot tasks are sticky to Julia thread 1 (Godot's main thread, where Julia was initialized). They run when that
# thread yields: immediately when started on the main thread, then during `JuliaLanguage::_frame` (process frame).

const MAIN_TID = 1
const POSTED = Any[]
const POSTED_LOCK = ReentrantLock()
const LIVE_TASKS = Threads.Atomic{Int}(0)
const MAX_PUMP_ROUNDS = 16

on_main_thread() = Threads.threadid() == MAIN_TID
in_godot_task() = get(task_local_storage(), :godot_task, false)::Bool

"Number of Godot tasks that have not finished (for tests and diagnostics)."
live_task_count() = LIVE_TASKS[]

function run_godot_task(f)
    task_local_storage(:godot_task, true)
    try
        return f()
    catch e
        # A task waiting for a signal of a freed object ends silently, like a canceled C# task.
        e isa SignalCancelled || Runtime.report_unhandled(e, catch_backtrace())
        return nothing
    finally
        Threads.atomic_sub!(LIVE_TASKS, 1)
    end
end

"""
    godot_task(f) -> Task

Run `f()` as a task on Godot's main thread (C#: an `async` method). Started from the main thread it runs at once
until its first wait. Continuations after `wait(to_signal(...))`, `wait(other_task)` or other Julia waits resume on
the main thread while Godot processes a frame, never on worker threads. Unhandled exceptions are reported with the
Julia stack trace (`push_error`). `fetch(task)` returns the result of `f`.
"""
function godot_task(f)
    t = Task(() -> run_godot_task(f))
    t.sticky = true
    ccall(:jl_set_task_tid, Cint, (Any, Cint), t, MAIN_TID - 1)
    Threads.atomic_add!(LIVE_TASKS, 1)
    on_main_thread() ? yield(t) : schedule(t)
    return t
end

"`@async_godot expr`: run `expr` as a [`godot_task`](@ref)."
macro async_godot(ex)
    return :(godot_task(() -> $(esc(ex))))
end

"""
    post(f)

Run `f()` on the main thread at the start of the next frame (C#: `SynchronizationContext.Post`). Safe to call from
any thread, e.g. to hand results of `Threads.@spawn` or `WorkerThreadPool` work back to the scene tree.
"""
function post(f)
    @lock POSTED_LOCK push!(POSTED, f)
    return nothing
end

main_runnable() = !isempty(Base.workqueue_for(MAIN_TID))

"Run posted functions and resume ready Godot tasks; called by the native host every process frame."
function pump_frame!()
    on_main_thread() || return nothing
    jobs = @lock POSTED_LOCK (isempty(POSTED) ? Any[] : splice!(POSTED, eachindex(POSTED)))
    for f in jobs
        try
            Base.invokelatest(f)
        catch e
            Runtime.report_unhandled(e, catch_backtrace())
        end
    end
    if LIVE_TASKS[] > 0 || Runtime.debug_server_running()
        # The debug server's socket tasks need libuv events, which only run when the main thread yields.
        Runtime.debug_server_running() && Base.process_events()
        for _ in 1:MAX_PUMP_ROUNDS
            yield()
            main_runnable() || break
        end
    end
    Runtime.debug_server_running() && Runtime.process_debug_requests!()
    return nothing
end
