# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Callable and Signal: engine-method callables and callables backed by any Julia callable.
# Ported from GodotSharp/Core/Callable.cs, Callable.generics.cs (MIT, Godot contributors).

"Callable for the engine method `method` of `obj` (C#: `new Callable(obj, method)`)."
function Callable(obj::GodotObject, method::Union{Symbol, AbstractString})
    r = Ref{RawCallable}()
    o = Ref(Internals.native_ptr(obj))
    sn = Ref(FFI.new_string_name(method))
    try
        GC.@preserve o sn begin
            argv = Ref((Base.unsafe_convert(Ptr{Cvoid}, o), Base.unsafe_convert(Ptr{Cvoid}, sn)))
            GC.@preserve argv ccall(FFI.constructor_ptr(FFI.variant_type(RawCallable), Int32(2)), Cvoid,
                                    (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}), r, argv)
        end
    finally
        FFI.destroy!(sn[])
    end
    return Callable(r[])
end

"""
    Callable(f; object = nothing)

Callable that invokes the Julia callable `f` — a function, closure or callable struct — with the Variant arguments
converted to Julia values (C#: `Callable.From(...)`). The result is converted back to a Variant (`nothing` → null).
`f` stays alive until Godot releases the last copy of the Callable. The Callable is tied to `object` (by default the
engine object `f` is bound to, see [`callable_target`](@ref)), so connections made with it are removed when that
object is freed, like C# delegates whose target is a `GodotObject`.
"""
Callable(f; object::Union{Nothing, GodotObject} = callable_target(f)) = Runtime.custom_callable(f, object)
Callable(c::Callable) = c

"Call the Callable from Julia (same as `call(c, args...)`)."
(c::Callable)(args...) = call(c, args...)

function _equal_as_variants(a, b)
    va = Internals.to_variant(a)
    vb = Internals.to_variant(b)
    try
        return _variant_equal(va, vb)
    finally
        FFI.destroy!(va)
        FFI.destroy!(vb)
    end
end
_string_of(x) = (v = Internals.to_variant(x); try _stringify(v) finally FFI.destroy!(v) end)

Base.:(==)(a::Callable, b::Callable) = _equal_as_variants(a, b)
Base.hash(c::Callable, h::UInt) = hash(GC.@preserve(c, Internals.builtin_call(Int64, :Callable, :hash, Internals.raw_ptr(c))), h)
Base.show(io::IO, c::Callable) = print(io, "Callable(", _string_of(c), ")")

"Signal `name` of `obj` (C#: `new Signal(obj, name)`)."
function Signal(obj::GodotObject, name::Union{Symbol, AbstractString})
    r = Ref{RawSignal}()
    o = Ref(Internals.native_ptr(obj))
    sn = Ref(FFI.new_string_name(name))
    try
        GC.@preserve o sn begin
            argv = Ref((Base.unsafe_convert(Ptr{Cvoid}, o), Base.unsafe_convert(Ptr{Cvoid}, sn)))
            GC.@preserve argv ccall(FFI.constructor_ptr(FFI.variant_type(RawSignal), Int32(2)), Cvoid,
                                    (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}), r, argv)
        end
    finally
        FFI.destroy!(sn[])
    end
    return Signal(r[])
end
Base.:(==)(a::Signal, b::Signal) = _equal_as_variants(a, b)
Base.show(io::IO, s::Signal) = print(io, "Signal(", _string_of(s), ")")
