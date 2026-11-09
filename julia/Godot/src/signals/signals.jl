# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Signals with Julia callables. Ported from GodotSharp/Core/Signal.cs and DelegateUtils.cs (MIT, Godot contributors).

"""
    callable_target(f) -> Union{Nothing, GodotObject}

The engine object a Julia callable is bound to (C#: `Delegate.Target`): `f` itself if it is an engine object, else
the first engine object captured by a closure or stored in a callable struct. A Callable made from `f` is tied to it,
so Godot removes connections through it when the target is freed. Functions and closures that capture no engine
object have no target; their connections last until disconnected or until the emitting object is freed.
"""
function callable_target(@nospecialize(f))
    f isa GodotObject && return f
    T = typeof(f)
    isstructtype(T) || return nothing
    for i in 1:fieldcount(T)
        isdefined(f, i) || continue
        x = getfield(f, i)
        x isa Core.Box && (x = isdefined(x, :contents) ? x.contents : nothing)
        x isa GodotObject && is_instance_valid(x) && return x
    end
    return nothing
end

as_callable(f) = f isa Callable ? f : Callable(f)

"""
    connect_callable(obj, signal, f, flags = 0) -> Callable

Connect `f` (a Julia callable or a `Callable`) to signal `signal` of `obj` and return the Callable, which
`disconnect` accepts. Throws if Godot refuses the connection.
"""
function connect_callable(obj::GodotObject, signal::Internals.StringNameLike, f, flags = 0)
    c = as_callable(f)
    err = connect(obj, signal, c, Integer(flags))
    err == OK || throw(ArgumentError("could not connect to signal $signal of $(class_name(obj)): $err"))
    return c
end

disconnect_callable(obj::GodotObject, signal::Internals.StringNameLike, f) = (disconnect(obj, signal, as_callable(f)); nothing)

"""
    connect(obj, signal, f::Function; flags = 0) -> Callable

Connect a Julia function or closure to a signal (C#: `obj.Connect(signal, Callable.From(f), flags)`; per-signal
helpers like `connect_pressed(button, f)` mirror C# events). Returns the Callable; `disconnect(obj, signal, f)` with
the same function also works. Connecting a `Callable` returns the engine's `Error` like C# `Connect`.
"""
connect(obj::GodotObject, signal::Internals.StringNameLike, f::Function; flags = 0) = connect_callable(obj, signal, f, flags)
disconnect(obj::GodotObject, signal::Internals.StringNameLike, f::Function) = disconnect_callable(obj, signal, f)
is_connected(obj::GodotObject, signal::Internals.StringNameLike, f::Function) = is_connected(obj, signal, Callable(f))

connect(s::Signal, f::Function; flags = 0) = connect_callable(get_object(s), get_name(s), f, flags)
disconnect(s::Signal, f::Function) = disconnect_callable(get_object(s), get_name(s), f)
is_connected(s::Signal, f::Function) = is_connected(s, Callable(f))

"Call the Julia function `f(args...)` at the end of the current frame (C#: `Callable.From(f).CallDeferred(args)`)."
call_deferred(f::Function, args...) = call_deferred(Callable(f), args...)
