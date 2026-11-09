# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Root types shared by generated and hand-written code.

"Root of the Godot class hierarchy (Godot's `Object`, renamed as in C#)."
abstract type GodotObject end

"Supertype of generated Godot enum types (`Node_ProcessMode`, `Error`, ...)."
abstract type GodotEnum end

"Supertype of generated Godot bitfield types; supports `|`, `&`, `xor` and `~`."
abstract type GodotBitfield <: GodotEnum end

"Godot `NodePath` (a path to a node and optionally a property, e.g. `NodePath(\"Player/Sprite:position\")`)."
struct NodePath
    path::String
end

"Godot `RID` (opaque resource handle used by servers)."
struct RID
    raw::FFI.RawRID
end
RID() = RID(FFI.RawRID((UInt64(0),)))

"""
    GDArray{T}

Godot `Array` with reference semantics (shared with the engine, not copied). `GDArray{Any}` (also `GDArray()`) is
untyped; `GDArray{T}` is a typed array (C#: `Godot.Collections.Array<T>`).
"""
mutable struct GDArray{T} <: AbstractVector{T}
    raw::FFI.RawArray
    GDArray{T}(raw::FFI.RawArray) where {T} = finalizer(Internals.finalize_builtin, new{T}(raw))
end
GDArray(raw::FFI.RawArray) = GDArray{Any}(raw)

"""
    GDDictionary{K, V}

Godot `Dictionary` with reference semantics. `GDDictionary{Any, Any}` (also `GDDictionary()`) is untyped;
`GDDictionary{K, V}` is typed (C#: `Godot.Collections.Dictionary<TKey, TValue>`).
"""
mutable struct GDDictionary{K, V} <: AbstractDict{K, V}
    raw::FFI.RawDictionary
    GDDictionary{K, V}(raw::FFI.RawDictionary) where {K, V} = finalizer(Internals.finalize_builtin, new{K, V}(raw))
end
GDDictionary(raw::FFI.RawDictionary) = GDDictionary{Any, Any}(raw)

"""
    Variant

An owned Godot `Variant` (C#: `Godot.Variant`). Construct with `Variant(x)`; extract with `convert(T, v)` or `T(v)`.
"""
mutable struct Variant
    raw::FFI.RawVariant
    Variant(raw::FFI.RawVariant) = finalizer(Internals.finalize_builtin, new(raw))
end

"Godot `Callable`."
mutable struct Callable
    raw::FFI.RawCallable
    Callable(raw::FFI.RawCallable) = finalizer(Internals.finalize_builtin, new(raw))
end

"Godot `Signal`."
mutable struct Signal
    raw::FFI.RawSignal
    Signal(raw::FFI.RawSignal) = finalizer(Internals.finalize_builtin, new(raw))
end

"Godot packed array with element type `T` (see the `Packed*Array` aliases)."
mutable struct PackedArray{T, R <: FFI.RawBuiltin} <: AbstractVector{T}
    raw::R
    PackedArray{T, R}(raw::R) where {T, R} = finalizer(Internals.finalize_builtin, new{T, R}(raw))
end
