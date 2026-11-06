# ADR 0006: Variant and collection marshalling

- Status: Accepted
- Date: 2026-11-04

## Context

Phase 06 ports C#'s `Variant`, `Godot.Collections.Array/Dictionary` (typed and untyped), packed-array marshalling, `StringName`, `NodePath`, `Callable` (including `Callable.From(lambda)`) and `Rid`. The builtin types also have about 600 engine methods (`String.capitalize`, `Array.pick_random`, `NodePath.get_subname`, ...).

## Decision

- **`Variant`** is an owning wrapper (`Variant(x)`, finalizer-released). Extraction uses `convert(T, v)` or `T(v)`, type-specialized per `T`, and throws `VariantConversionError` on mismatch. Integers and floats convert with checked range conversion (an int Variant converts to `Float64`, not the reverse). String, StringName and NodePath convert into each other. Object targets return `Union{Nothing, T}`. Generated bindings and script instances use the same `from_variant(T, ...)` / `to_variant!` functions.
- **`isvarianttype(T)`** is the `[MustBeVariant]` equivalent. Fixed-size integers and floats widen to Godot's `int`/`float`, as in C#.
- **`Vector{T}` marshals like C#'s `T[]`**: packed arrays for `UInt8`, `Int32`, `Int64`, `Float32`, `Float64`, `String`, `Vector2/3/4` and `Color`, and an `Array` otherwise. Packed arrays convert to and from `Vector` with `memcpy`. `unsafe_wrap(Array, p)` gives a zero-copy view. Obtaining the view triggers Godot's copy-on-write, so the buffer becomes unique; the view is invalid after a resize, a copy, or a hand-off to the engine (documented on the method).
- **StringName is `Symbol`** (`const StringName = Symbol`): both are interned, and the bindings already return `Symbol`. **NodePath** stays a small Julia struct holding the path text, converted to a native NodePath per call.
- **Typed containers are type parameters**: `GDArray{T} <: AbstractVector{T}` and `GDDictionary{K,V} <: AbstractDict{K,V}`. `GDArray{Any}` and `GDDictionary{Any,Any}` are untyped. Constructing a typed container sets Godot's typed-container info. Arrays and dictionaries returned by the engine are wrapped with their engine element types; the generator maps `typedarray::Node` to `GDArray{Node}`. Wrapping as an incompatible `T` throws. Elements are converted to `T` before reaching the engine, so type violations raise Julia errors instead of Godot's printed errors. Object element types read as `Union{Nothing, T}`. Reference semantics match C#: containers are shared with the engine. `copy` is Godot's shallow `duplicate()`, `deepcopy` is `duplicate(true)`, and read-only containers throw on mutation.
- **Builtin methods are generated** (`generated/builtin_methods.jl`) for String (on any `AbstractString`), StringName (on `Symbol`), NodePath, RID, Callable, Signal, Array, Dictionary and the packed arrays. Static methods take the type: `num(String, 3.14, 2)`. Methods whose names are Base functions with a different Julia meaning are not bound, because the Julia equivalent applies: `length`, `split`, `join`, `replace`, `size`, `get`, `keys`, `sort`, `map`, ... (113 in total, listed in `binding_report.txt`). The exception is Callable `bind`, which extends `Base.bind` because the receiver type is ours.
- **Julia callables as Callables**: `Callable(f)` creates a GDExtension custom callable. `f` is pinned and unpinned in `free_func` when Godot drops the last reference. `hash`, `==` (same Julia object), ordering, `to_string` and `get_argument_count` are implemented. Arguments arrive as Julia values. A result that cannot be stored in a Variant becomes null, so any Julia function works as a signal handler. `Callable(f; object = obj)` ties the callable to an object (for auto-disconnect, phase 10).

## Consequences

- Every Variant type round-trips through GDScript, and creating and freeing 1M Variants and Arrays leaves engine memory stable (`tests/integration/variant`).
- C# users will notice that `StringName` is `Symbol` and that Base-named builtin methods use Julia's own functions instead (e.g. `split(s, ",")` rather than `s.split(",")`). This goes in the phase 16 translation table.
