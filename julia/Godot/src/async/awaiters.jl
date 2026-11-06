# Awaiting signals: SignalAwaiter / ToSignal parity. Ported from GodotSharp/Core/SignalAwaiter.cs (MIT, Godot contributors).

"Raised in a task waiting for a signal whose emitting object was freed (C#: a canceled task)."
struct SignalCancelled <: Exception
    signal::Symbol
end
Base.showerror(io::IO, e::SignalCancelled) = print(io, "SignalCancelled: the object emitting `", e.signal, "` was freed")

"""
Awaitable for the next emission of a signal, returned by [`to_signal`](@ref); `wait` returns the signal arguments as
a tuple (C#: `await ToSignal(obj, name)` returning `Variant[]`).
"""
mutable struct SignalAwaiter
    const signal::Symbol
    const event::Base.Event
    @atomic args::Union{Nothing, Tuple}
    @atomic cancelled::Bool
end

function (a::SignalAwaiter)(args...)
    @atomic a.args = args
    notify(a.event)
    return nothing
end

# The one-shot connection is released after the emission, or when the emitting object is freed (then: cancel).
function Runtime.callable_freed(a::SignalAwaiter)
    if (@atomic a.args) === nothing
        @atomic a.cancelled = true
        notify(a.event)
    end
    return nothing
end

"""
    to_signal(obj, signal) -> SignalAwaiter
    to_signal(s::Signal) -> SignalAwaiter

Awaitable for the next emission of `signal` (C#: `ToSignal`). Use `wait(...)` or `@await` inside a
[`godot_task`](@ref); waiting throws [`SignalCancelled`](@ref) if `obj` is freed first.
"""
function to_signal(obj::GodotObject, signal::Internals.StringNameLike)
    a = SignalAwaiter(Symbol(signal), Base.Event(), nothing, false)
    c = Callable(a; object = nothing)
    err = connect(obj, signal, c, Integer(GodotObject_CONNECT_ONE_SHOT))
    # Release Julia's copy now so the connection holds the only reference (freeing the source then cancels).
    finalize(c)
    err == OK || throw(ArgumentError("could not await signal $signal of $(class_name(obj)): $err"))
    return a
end
to_signal(s::Signal) = to_signal(get_object(s), get_name(s))

function Base.wait(a::SignalAwaiter)
    if (@atomic a.args) === nothing && !(@atomic a.cancelled)
        on_main_thread() && !in_godot_task() &&
            error("waiting for signal $(a.signal) on the main thread outside a Godot task would block the engine; " *
                  "start a task with godot_task/@async_godot")
        wait(a.event)
    end
    args = @atomic a.args
    args === nothing && throw(SignalCancelled(a.signal))
    return args
end

Base.wait(s::Signal) = wait(to_signal(s))

"`@await x` is `wait(x)`: suspend the current Godot task until `x` (a signal awaiter, task, ...) completes."
macro await(ex)
    return :(wait($(esc(ex))))
end

"Awaitable for the next process frame of `node`'s tree (C#: `await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame)`)."
next_frame(node::Node) = to_signal(get_tree(node), :process_frame)

"Awaitable for the next physics frame of `node`'s tree."
next_physics_frame(node::Node) = to_signal(get_tree(node), :physics_frame)

"Awaitable that fires after `seconds` (C#: `await ToSignal(GetTree().CreateTimer(seconds), Timer.SignalName.Timeout)`)."
delay(node::Node, seconds::Real) = to_signal(create_timer(get_tree(node), seconds), :timeout)
