---
name: book-ch09-variant-collections
description: "Book chapter 9: the logic behind gdjl-06-variant-collections — Variant, strings, typed collections, packed arrays and Callables across two type systems."
agent: agent
---
Write chapter 9 of the book, `docs/book/09-variant-collections.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-06-variant-collections](../gdjl-06-variant-collections.prompt.md).

## Focus

- **Pointing at both code and docs as references** (`Variant.cs`, `Marshaling.cs`, and the `c_sharp_variant`/`c_sharp_collections` pages). Docs give the user-visible contract; code gives the edge cases.
- **Semantics stated precisely.** "Reference semantics like C#: shared with the engine, not copied." Why ambiguous semantics in a prompt produce code that passes tests but surprises users.
- **A trait that later phases depend on.** `isvarianttype(T)` is designed here to support the `[MustBeVariant]`-equivalent diagnostics in phase 09. Prompts that plan for future phases.
- **Type stability as a requirement** ("no dynamic dispatch on hot paths") and how the design (`Internals.from_variant(T, raw)` methods) satisfies it.
- **Leak tests at scale** (1M create/destroy) and GC of closure Callables after disconnect.

## Leads to Verify

- ADR 0006: `StringName === Symbol`. A bold, idiomatic decision; explain its trade-offs.
- Typed containers `GDArray{T}`/`GDDictionary{K,V}` and how engine typed containers are wrapped.
- Custom callables pin a Julia object and are released after the last Godot reference.
- Julia-language traps found here: `@eval $T(...) = ...` with an interpolated parametric type fails ("invalid function name"), so `(::Type{$T})(...)` is used. Unqualified Base constructor extension such as `Bool(v::X)` warns in 1.13. Use these as examples of model knowledge lagging behind a language release.
- The generator emits `generated/builtin_methods.jl` for non-math builtin methods (methods named like Base functions are skipped).

## Artifacts to Inspect

`julia/Godot/src/variant/`, `julia/Godot/src/runtime/callables.jl`, `docs/adr/0006-variant-collections.md`, `tests/integration/variant/` (including its GDScript `helper.gd` identity functions).

## Try It Yourself

Ask the agent to add a round-trip test for one more Variant type through the GDScript identity helper, and to state up front which ownership rule applies.

Parity rows: 3.4–3.10, 3.12, 3.13. Navigation: previous chapter 8, next chapter 10.
