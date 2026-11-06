# ADR 0009: Script authoring API (exports, signals, RPC, diagnostics)

- Status: Accepted
- Date: 2026-11-06

## Context

Phase 09 ports C#'s attributes and source generators (`[Export*]`, `[Signal]`, `[Tool]`, `[GlobalClass]`, `[Icon]`, `[Rpc]`, `ScriptPropertiesGenerator`, `ScriptMethodsGenerator`, `ScriptSignalsGenerator`, `MustBeVariantAnalyzer`, ...) on top of the `@godot_class` model of ADR 0008.

## Decision

- **Annotations live inside `@godot_class`** and are rewritten syntactically; they are not standalone macros. A field annotation precedes the declaration. Arguments are a tuple separated by a space (`@export_range (0, 100, 1; or_greater = true) hp::Int = 100`), because `@m(args) decl` is not valid Julia syntax. Single arguments may be bare (`@export_placeholder "Name..." s::String`). Groups use the call form (`@export_group("Visuals"; prefix = "visual_")`). Argument values are evaluated in the script module, so constants and engine enums work.
- **Hints derived from types** follow C#: `@enum`/Godot enums become `PROPERTY_HINT_ENUM`, bitfields `FLAGS`, `Node`/`Resource` types `NODE_TYPE`/`RESOURCE_TYPE` (using the global class name of `@global_class` scripts), and typed `GDArray{T}`/`Vector{T}`/`GDDictionary{K,V}` `ARRAY_TYPE`/`DICTIONARY_TYPE` with C#'s `type/hint:hint_string` element format. Annotations override hint, hint string or usage.
- **Static generated code**: each class gets type-stable `script_get_field`/`script_set_field!` methods (a chain of constant `Symbol` comparisons, like C#'s generated `GetGodotClassPropertyValue`), `getproperty`/`setproperty!` that prefer Julia fields over inherited engine properties, and per-method call thunks compiled on first use that convert Variants to the declared parameter types (like `InvokeGodotClassMethod`). Overloaded methods fall back to dynamic dispatch.
- **Signals** generate `emit_<name>(self, args...)` and `connect_<name>(self, f; flags)` in the script module. They are not exposed as engine methods.
- **Name tables** are functions returning constant named tuples: `SignalName(T).hit`, `PropertyName(T).speed`, `MethodName(T)`. Julia cannot add properties to a type, so `T.SignalName` is not possible. `Symbol` is `StringName`, and conversions use the process-wide `StringName` cache.
- **Tool buttons** are virtual properties, not stored fields: `@export_tool_button ("Text", "Icon") name = function_name` returns a `Callable` running the script function on the instance.
- **`@rpc`** wraps a script function definition and feeds `_get_rpc_config`. Defaults follow C#'s `[Rpc]`: authority, call_remote, **reliable**, channel 0. GDScript's `@rpc` defaults to unreliable.
- **Static methods** are functions whose first parameter is `::Type{T}`. They are reported by `_has_static_method` and listed with `METHOD_FLAG_STATIC`. **Deviation**: a GDExtension script class cannot intercept arbitrary `Script.method()` calls (there is no `callp` virtual on `ScriptExtension`), so the engine calls them through the method `JuliaScript.call_static(method, args...)`. C# calls them as `Script.Method()` because it is an engine module. Julia code calls them directly (`double_it(Player, 21)`).
- **Diagnostics** are `ScriptDiagnostic(code, message)` exceptions raised at macro expansion or class definition. They are reported as `res://File.jl:<line>: GDJLnnnn: message`. Codes mirror C#'s `GDnnnn` (table in `docs/diagnostics.md`, checked by a unit test).

## Consequences

- Script properties read from GDScript cost about 0.16 µs (was 1.1 µs with dynamic access). Method calls are dominated by the engine/bridge round trip (see `docs/perf.md`).
- Row 5.16 is `DONE` with the documented `call_static` deviation, not a `GAP`: static methods are visible to and callable from the engine, through a different call syntax.
