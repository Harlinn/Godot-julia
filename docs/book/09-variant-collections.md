# 9. Variant and Collections: Semantics, Stated Precisely

Godot has one universal value type: **`Variant`**.

Every value that crosses a dynamic boundary in the engine travels as a Variant:

- arguments to `Object.call`,
- signal parameters,
- property values,
- array elements,
- dictionary keys and values,
- values passed between GDScript, C# and C++.

A Variant can hold `null`, booleans, integers, floats, strings, the math types from chapter 8, objects, arrays, dictionaries, packed arrays, callables and signals.

Phase 6 builds Julia's side of that boundary. It covers:

- `Variant` itself,
- the string types (`String`, `StringName`, `NodePath`),
- typed and untyped arrays and dictionaries,
- the ten packed array types,
- `Callable`, including Callables built from any Julia function,
- `RID`.

Two type systems meet here. Their mismatches are where subtle bugs live. Is a Godot array a copy or a reference? Who owns a Julia closure after Godot stores it in a signal connection? What happens when you put a string into an array declared to hold integers?

The prompt's main technique is simple: answer those questions *in the prompt*, one sentence each, before the agent can answer them differently.

The phase needs the FFI layer (chapter 6) for the raw Variant ABI and the math types (chapter 8) to convert. Both the object model (chapter 10) and scripts (chapter 11) depend on its conversion functions.

## The Prompt

[`.github/prompts/gdjl-06-variant-collections.prompt.md`](../../.github/prompts/gdjl-06-variant-collections.prompt.md):

```markdown
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
```

## Anatomy of the Prompt

### References to Both Code and Documentation

The reference list has two parts:

- nine C# source files (`Variant.cs`, `Marshaling.cs`, `Array.cs`, …),
- two documentation pages (`c_sharp_variant.rst`, `c_sharp_collections.rst`).

They answer different questions.

The documentation states the **user-visible contract**. It's what a C# developer is told to expect when putting an `int` into a Variant or passing an array to the engine.

The code reveals the **edge cases** the documentation glosses over: checked numeric conversions, how typed-array information is set, what happens to `null`.

Give an agent only code, and it tends to port accidents of implementation. Give it only docs, and it tends to miss the corner cases. Give it both.

### Semantics in One Sentence Each

The most valuable sentences in this prompt are the short ones that settle semantics:

- *"Reference semantics like C#: shared with the engine, not copied."*
- *"`deepcopy` → Godot `duplicate(true)`."*
- *"all `Integer`/`AbstractFloat` (widened to `Int64`/`Float64` like C#)"*
- *"Julia `Vector{T}` of packable `T` (→ `Packed*Array`, like C# `T[]`)"*
- *"copy-on-write rules documented"*
- *"pin the Julia object, unpin on free"*

Each one closes a question that an implementation must answer one way or the other.

Without them, the agent would still answer each question. But it would answer implicitly, in code, possibly differently in different files. And the tests would pass either way.

Copy semantics are a good example. A test that builds an array and reads it back passes whether arrays are copied or shared. The difference only shows up when someone modifies the array on one side and expects to see the change on the other.

Here's the key point: **ambiguity in a prompt does not produce failing tests.** It produces code that passes its tests and surprises the people who use it.

### A Trait Designed for a Later Phase

Requirement 2 asks for `isvarianttype(T)` and says why: *"This trait backs the `[MustBeVariant]` equivalent in phase 09."*

In C#, `[MustBeVariant]` is an **analyzer**. At compile time, it rejects generic arguments that can't be stored in a Variant.

Julia has no compile-time analyzers. Phase 9's authoring macros can still check types when a script is loaded, though, as long as a single function answers "can this type live in a Variant?".

By asking for the trait now and naming its future consumer, the prompt makes sure the answer lives in one place. Conversions, typed containers, exports and signal declarations all share it. It's a small piece of architecture planned in the prompt rather than discovered later.

### Performance Stated as Type Stability

Requirement 1 says: *"Conversion functions must be type-stable and specialized per type (no dynamic dispatch on hot paths)."*

Why does this matter? Variant conversion runs on every engine call that returns or accepts a Variant, and on every script callback.

In Julia, a conversion function whose return type depends on runtime data forces every caller to handle "any type". That means allocation and dynamic dispatch.

So the requirement tells the agent to write **one method per target type** (`from_variant(::Type{Int64}, v)`, `from_variant(::Type{Vector2}, v)`, …). Not one generic function with a big `if` on the stored type.

### Entry Points for Later Phases

Requirement 8 names two functions, `to_variant!(dst, x)` and `from_variant(T, src)`, *"used by script instances and generated bindings."*

Like the trait, these exist for consumers that don't exist yet. Fixing their names and signatures now means phase 8 (scripts) and the regenerated bindings will call the same conversions instead of growing their own.

### Tests Aimed at the Boundary

The four tests target exactly the places where the two type systems meet:

1. **Round-trip every type through GDScript.** Converting from Julia to a Variant and back proves little, because the same code could be wrong in both directions. Passing the value through a GDScript identity function makes *Godot* store and return it.
2. **Typed arrays enforce their types.**
3. **A leak test at scale.** One million Variants and Arrays, with engine memory stable.
4. **A closure Callable** invoked from GDScript and then garbage-collected after disconnect. This is the hardest lifetime case in the phase: a Julia object referenced only by an engine data structure.

## What the Agent Built

[ADR 0006](../adr/0006-variant-collections.md) records the design. The code lives in [`julia/Godot/src/variant/`](../../julia/Godot/src/variant):

- `variant.jl`,
- `strings.jl`,
- `array.jl`,
- `dictionary.jl`,
- `packed.jl`,
- `callable.jl`.

On top of those, [`runtime/callables.jl`](../../julia/Godot/src/runtime/callables.jl) holds the custom-callable entry points.

### `StringName` Is `Symbol`

The boldest decision in the ADR fits on one line of [`strings.jl`](../../julia/Godot/src/variant/strings.jl):

```julia
const StringName = Symbol
```

Look at what the two types have in common:

- Godot's `StringName` is an interned string, used for method, property and signal names, and compared by pointer.
- Julia's `Symbol` is also an interned string, used for exactly the same purposes.

The generated bindings were already returning `Symbol` for names. So instead of adding a wrapper type that would need conversions in both directions, the agent made the two **the same type**.

`get_name(node) === :Player` reads naturally. And `StringName("x") === :x` is a test, not a curiosity.

The trade-off is recorded in the ADR's consequences. C# users will notice that `StringName` is `Symbol`, so it goes in the phase 16 translation table.

`NodePath`, by contrast, stays a small Julia struct holding the path text. It's converted to a native NodePath per call, because it has no natural Julia equivalent.

### `Variant` and Typed Conversions

`Variant` is an **owning wrapper**. A finalizer releases its native value (via the main thread, as chapter 10 explains).

Extraction follows the per-type rule. Each target type gets its own method of `Internals.from_variant`. Where many types share a pattern, the methods are generated with `@eval` ([`variant.jl`](../../julia/Godot/src/variant/variant.jl)):

```julia
function Internals.from_variant(::Type{A}, v::RawVariant) where {A <: GDArray}
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_ARRAY || _conv_error(A, vt)
    return _wrap_array(A, FFI.from_variant(RawArray, v))
end
```

A few behaviors are worth knowing:

- A mismatch throws `VariantConversionError` with a readable message (*"cannot convert a Variant holding TYPE_INT to String"*).
- Integer conversions are range-checked. `Int8(Variant(1000))` throws `InexactError` instead of silently wrapping around.
- Object targets return `Union{Nothing, T}`, because any object slot can hold `null`.

### `isvarianttype`

The trait is a dozen lines. Its docstring doubles as the definition of "Variant-compatible":

```julia
isvarianttype(::Type) = false
isvarianttype(::Type{<:Union{Bool, _VariantInt, _VariantFloat, AbstractString, Symbol, NodePath, RID, MathType,
                             Callable, Signal, GodotObject, GodotEnum, GDArray, GDDictionary, PackedArray, Variant,
                             Nothing}}) = true
isvarianttype(::Type{Vector{T}}) where {T} = isvarianttype(T)
isvarianttype(::Type{<:Base.Enum}) = true
```

Phase 9 later built three analyzer-style diagnostics on top of it (`GDJL0102`, `GDJL0202`, `GDJL0301`), for exports, signal parameters and typed-collection elements. That completed matrix row 3.13, which this phase could only mark `PARTIAL`.

### Typed Containers as Type Parameters

`GDArray{T} <: AbstractVector{T}` and `GDDictionary{K,V} <: AbstractDict{K,V}` are **ordinary Julia collections**. `push!`, `append!`, indexing, iteration, `sum` and `Dict(d)` all work.

- `GDArray{Any}` is the untyped array.
- Constructing a typed container sets Godot's typed-array information, so GDScript sees an `Array[int]`.
- Containers returned by the engine come back with their engine element types. `get_children(node)` returns a `GDArray{Node}`, because the generator maps `typedarray::Node` to it.

The semantics are the ones the prompt dictated:

- containers are shared with the engine,
- `copy` is Godot's shallow `duplicate()`,
- `deepcopy` is `duplicate(true)`,
- read-only containers throw on mutation.

### Packed Arrays and an Honest `unsafe_wrap`

The ten packed array types are `AbstractVector`s. They convert to and from `Vector{T}` with a memory copy. A `Vector{Float32}` passed to the engine becomes a `PackedFloat32Array`, just as a `float[]` does in C#.

For speed, there's also a **zero-copy view**. Its docstring in [`packed.jl`](../../julia/Godot/src/variant/packed.jl) is a model of how to document an unsafe API:

```julia
"""
    unsafe_wrap(Array, p::PackedArray) -> Vector

Zero-copy view of the elements of `p` (isbits element types only). Writes go straight into Godot's buffer; obtaining the
view makes the buffer unique (copy-on-write). The view is invalid after `p` is resized, garbage collected, or copied
(including being passed to the engine, which shares the buffer); keep `p` alive with `GC.@preserve` while using it.
"""
```

The prompt asked for *"copy-on-write rules documented"*. The result is a docstring that tells you exactly when the view becomes dangerous, placed right where you'll see it.

### About 600 Builtin Methods, and 113 That Were Left Out

Godot's builtin types have about 600 engine methods: `String.capitalize`, `Array.pick_random`, `NodePath.get_subname`, and so on.

The generator from chapter 7 now emits them into `generated/builtin_methods.jl`:

- String methods work on any Julia `AbstractString`.
- StringName methods work on `Symbol`.

So `capitalize("hello_world")` and `begins_with(:Godot, "Go")` both work.

113 methods were deliberately *not* bound. Their names are Julia Base functions with a different meaning: `length`, `split`, `join`, `replace`, `keys`, `sort`, …

For those, the Julia function applies. In Julia you write `split(s, ",")`, not `s.split(",")`. Each skipped method is listed in `binding_report.txt`.

### Callables from Any Julia Function

`Callable(f)` turns any Julia function, closure or callable struct into a Godot Callable. It uses GDExtension's **custom-callable interface** ([`runtime/callables.jl`](../../julia/Godot/src/runtime/callables.jl)).

The Julia object is pinned (chapter 5). The pin is released when Godot frees the callable:

```julia
function _callable_free(ud::Ptr{Cvoid})::Cvoid
    @godot_entry nothing begin
        id = UInt64(UInt(ud))
        box = deref(id)::JuliaCallable
        unpin(id)
        callable_freed(box.f)
        nothing
    end
end
```

Every entry point is wrapped in `@godot_entry` and registered through a guarded trampoline. Hash, equality (*"same Julia object"*), ordering, `to_string` and argument count are all implemented.

There's one deliberate leniency. If a Julia function returns something that can't be stored in a Variant, the result becomes `null` instead of an error. That way *any* Julia function works as a signal handler, no matter what its last expression returns.

## Where Reality Pushed Back

### Julia Metaprogramming Traps

Much of this phase is generated with `@eval` loops over many types. Two Julia details caught the agent out, and both went into its memory notes:

- **Interpolated parametric types.** `@eval $T(v::Variant) = ...` with an interpolated *parametric* type fails with *"invalid function name"*. The fix is to define the method on the type's type explicitly: `(::Type{$T})(v::Variant) = ...`.
- **Unqualified Base constructors.** Extending a Base constructor without qualification, as in `Bool(v::X) = ...`, triggers a warning in Julia 1.13. The same `(::Type{Bool})(...)` form avoids it.

You'll see the pattern throughout the code:

```julia
for T in (Bool, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64, String, Symbol, NodePath,
          RID, Callable, Signal, MATH_TYPES...)
    @eval (::Type{$T})(v::Variant) = Internals.from_variant($T, v.raw)
end
```

These are language-version details. They're exactly the kind of thing a model trained mostly on older Julia code gets wrong with confidence.

The agent found them by running the code, not by remembering. Then it wrote them down so the next session wouldn't have to find them again.

### Typed Arrays: Julia Errors Instead of Godot Errors

The prompt says *"Typed array type enforcement mirrors Godot errors."* The agent deviated, and ADR 0006 explains how:

> Elements are converted to `T` before reaching the engine, so type violations raise Julia errors instead of Godot's printed errors.

Godot's own enforcement *prints* an error and ignores the operation. In Julia, that would mean `push!(a, "x")` on a `GDArray{Int64}` silently does nothing except log a message.

Converting first and throwing a Julia exception gives you the behavior you'd expect as a Julia programmer:

- `MethodError` for a wrong type,
- `InexactError` for `1.5` into an integer array.

The test pins it down:

```julia
        t = GDArray{Int64}([1, 2])
        @test eltype(t) === Int64 && t[2] === 2
        @test is_typed(t) && get_typed_builtin(t) == Int(TYPE_INT)
        @test_throws MethodError push!(t, "x")
        @test_throws InexactError push!(t, 1.5)
```

"Mirror Godot" was a loose phrase in the prompt. The agent read it as mirroring the **rule** (only integers allowed), not the **failure mode** (print and ignore). Then it recorded that choice.

Whether you agree with it or not, you can see it and change it.

### Startup Kept Growing

About 600 generated builtin methods have a cost. The report: *"the Julia part of engine startup is now about 1.0 s, up from 0.88 s."*

As in every previous phase, the number went into [`docs/perf.md`](../perf.md), and the fix was assigned to phase 14.

### Scope Deferred Openly

Two pieces couldn't be finished here, and the report said so:

- **Typed containers of user script classes** (a `GDArray{Player}` where `Player` is a Julia script) need the script model of phases 8 and 9.
- **Row 3.13** (`[MustBeVariant]`) went to `PARTIAL`. The trait exists, but the load-time diagnostics belong to phase 9.

### A Design That Hot Reload Revisited

Here's the custom-callable box as it looks today:

```julia
"What a custom Callable pins: the Julia callable (swapped on hot reload) and the hash Godot saw at creation."
mutable struct JuliaCallable
    f::Any
    const hash::UInt32
end
```

The comment *"swapped on hot reload"* is a later addition.

In phase 11 (chapter 14), reloading a script must make existing signal connections call the *new* version of a closure. But Godot has already stored the callable's hash in its internal structures, so the hash must not change.

Pinning a mutable box with a constant hash, instead of the function itself, solved both problems.

So a decision made in phase 6 was revised in phase 11. The struct records why, and the tests of both phases still pass.

## Closing the Loop

The integration project [`tests/integration/variant/`](../../tests/integration/variant) is tagged `# parity: 3.4–3.10, 3.12, 3.13`. It pairs a Julia test file with a small GDScript helper ([`helper.gd`](../../tests/integration/variant/helper.gd)). The helper's whole job is to be "the other side":

```gdscript
func id(x):
	return x


func typed_ints() -> Array[int]:
	return [1, 2, 3]
```

The **round-trip test** sends every Variant type through `id`, from `nothing` and `"héllo ✓ 世界"` to `Projection`. It checks both the value and the *type* that comes back:

```julia
        for x in values
            back = roundtrip(helper, x)
            @test typeof(back) == typeof(x)
            @test back == x
        end
        @test roundtrip(helper, Int32(5)) === 5
        @test roundtrip(helper, 1.5f0) === 1.5
```

The last two lines check the widening rule from the prompt. An `Int32` goes in and an `Int64` comes out, exactly as in C#.

The **reference-semantics test** modifies an array returned from GDScript and checks the original.

The **Callable test** measures *liveness* directly through the pin count:

```julia
        pins = Runtime.pin_count()
        received, alive_after_connect = signal_roundtrip(helper)
        @test received == "hello" && alive_after_connect == pins + 1
        collect_garbage()
        @test Runtime.pin_count() == pins            # the closure was released after the last Godot reference
```

The **leak test** creates one million Variants and one million Arrays in batches. It requires Godot's static memory to grow by less than a megabyte.

The phase 6 report counted 162 in-engine checks in this project. Run them yourself:

```powershell
julia tests/integration/run.jl variant
julia --project=julia/Godot -e "using Pkg; Pkg.test()"
```

## Techniques to Reuse

- **Settle semantics in the prompt.** Write one sentence each for copy vs reference, widening, ownership and copy-on-write. Ambiguity produces passing tests and surprised users.
- **Give both the contract and the implementation as references.** Docs tell the agent what users are promised. Code shows it the edge cases.
- **Design shared building blocks for their future consumers.** Name the later phase that will use a trait or entry point, so there's exactly one of it.
- **Round-trip through the other side.** Verify a conversion by letting the *other* system store and return the value, not by converting back and forth in your own code.
- **Measure lifetime directly.** Pin counts and memory statistics turn "it was garbage collected" into a testable claim.
- **Document unsafe APIs where they're used.** The docstring of `unsafe_wrap` lists exactly when the view becomes invalid.

## Try It Yourself

1. Run `julia tests/integration/run.jl variant`. Then add a `PackedVector4Array` element check to the round-trip test, or another Julia type you think should be Variant-compatible. See what the trait says.
2. Open the **Ask** agent and ask: *"What happens, step by step, when GDScript calls a Julia closure wrapped in `Callable(f)` and later disconnects it? Where is the closure pinned and unpinned?"* Check the answer against `runtime/callables.jl` and the Callable testset.
3. Discuss with the agent whether typed arrays *should* mirror Godot's print-and-ignore behavior instead of throwing. Ask it to list what would have to change (ADR 0006, the tests, user docs) if you decided to switch.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 3.4 | `Variant` with conversions | DONE (ADR 0006; `tests/integration/variant`) |
| 3.5 | String marshalling | DONE (UTF-8 ↔ UTF-32 via the interface; String methods generated on `AbstractString`) |
| 3.6 | `StringName`, `NodePath` | DONE (`StringName === Symbol`, ADR 0006) |
| 3.7 | `Array`, typed `Array<T>` | DONE (`GDArray`, `GDArray{T}` as `AbstractVector`) |
| 3.8 | `Dictionary`, typed `Dictionary<K,V>` | DONE (`GDDictionary`, `GDDictionary{K,V}` as `AbstractDict`) |
| 3.9 | Packed arrays | DONE (`Vector{T}` ↔ packed via memcpy; zero-copy `unsafe_wrap`) |
| 3.10 | `Callable`, including from lambdas | DONE (custom callables; tied to the captured engine object for auto-disconnect in phase 10) |
| 3.12 | `Rid` | DONE |
| 3.13 | `[MustBeVariant]` | DONE (`isvarianttype` trait here; GDJL0102/GDJL0202/GDJL0301 diagnostics in phase 09) |

Row 3.13 ended this phase as `PARTIAL`, as the prompt anticipated, and was completed in phase 9.

---
[← Previous: Builtin Math](08-builtin-math.md) · [Contents](README.md) · [Next: The Object Model →](10-object-model.md)
