---
name: gdjl-06-variant-collections
description: "Phase 6: Variant, String/StringName/NodePath, typed Array/Dictionary, Packed arrays, Callable and RID marshalling for Julia."
agent: agent
---
Implement Variant and the non-math builtin types in `julia/Godot/src/variant/`. Follow the [project instructions](../copilot-instructions.md). Behavioral references: `GodotSharp/Core/Variant.cs`, `NativeInterop/VariantUtils*.cs`, `Marshaling.cs`, `Array.cs`, `Dictionary.cs`, `StringName.cs`, `NodePath.cs`, `Callable.cs`, `Rid.cs`, and the docs pages `c_sharp_variant.rst` and `c_sharp_collections.rst`.

## Requirements

1. **Variant**: `Variant` owning wrapper with `variant_type(v)`, constructors from every Variant-compatible Julia type, `convert(T, v)` / `T(v)` extraction with clear errors on mismatch, `nil`/`nothing` mapping. Conversion functions must be type-stable and specialized per type (no dynamic dispatch on hot paths).
2. **Variant-compatible type trait**: `isvarianttype(::Type)` covering `Bool`, all `Integer`/`AbstractFloat` (widened to `Int64`/`Float64` like C#), `String`, `Symbol` (→ `StringName`), builtins, `GodotObject` subtypes, `GDArray{T}`, `GDDictionary{K,V}`, packed arrays, Julia `Vector{T}` of packable `T` (→ `Packed*Array`, like C# `T[]`), enums/bitfields. This trait backs the `[MustBeVariant]` equivalent in phase 09.
3. **Strings**: Julia `String` ↔ Godot `String` (UTF-32 internally — convert efficiently), `StringName` (interned, cached, `Symbol` convertible), `NodePath` (`NodePath("A/B:prop")`, convertible from `String`). Methods from the builtin API available on each.
4. **Collections**: `GDArray` (untyped) and `GDArray{T}` (typed; sets the typed-array script/class info) implementing `AbstractVector` (`getindex`, `setindex!`, `push!`, `append!`, `length`, iteration, `copy`, `deepcopy` → Godot `duplicate(true)`). `GDDictionary` / `GDDictionary{K,V}` implementing `AbstractDict`. Reference semantics like C#: shared with the engine, not copied. Read-only arrays respected.
5. **Packed arrays**: `PackedByteArray`, `PackedInt32Array`, `PackedInt64Array`, `PackedFloat32Array`, `PackedFloat64Array`, `PackedStringArray`, `PackedVector2Array`, `PackedVector3Array`, `PackedVector4Array`, `PackedColorArray` as `AbstractVector` with zero-copy `unsafe_wrap` views for isbits element types (copy-on-write rules documented), and conversion from/to `Vector{T}`.
6. **Callable**: from engine method (`Callable(obj, :method)`) and from any Julia callable — functions, closures, callable structs — via `callable_custom_create2` (pin the Julia object, unpin on free, implement hash/equal/to_string/get_argument_count). `call(c, args...)`, `bind`, `unbind`, `call_deferred`.
7. **RID**: `RID` isbits wrapper with `is_valid`, `get_id`, comparison.
8. **Marshalling entry points** used by script instances and generated bindings: `to_variant!(dst::Ptr{Variant}, x)` and `from_variant(T, src::Ptr{Variant})`.

## Tests

- Round-trip every Variant type through the engine (`Variant` → GDScript identity function → back).
- Typed array type enforcement mirrors Godot errors.
- Leak test: create/destroy 1M Variants/Arrays; memory stable.
- Julia closure Callable invoked from GDScript, then garbage collected after disconnect.

Update parity rows 3.4–3.10, 3.12, 3.13 (partial).
