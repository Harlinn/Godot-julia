---
name: gdjl-04-bindings-generator
description: "Phase 4: GodotBindgen — generate the full Julia engine API from extension_api.json, matching C#'s bindings_generator."
agent: agent
---
Implement `julia/GodotBindgen` to generate `julia/Godot/src/generated/` from `extension_api.json` (with docs). Follow the [project instructions](../copilot-instructions.md). Behavioral reference: `modules/mono/editor/bindings_generator.cpp` and the generated output of `GodotSharp` / `GodotSharpEditor` (study what C# exposes and how it names/organizes it).

## Output Requirements

1. **Classes**: for every class, `abstract type X <: Parent end` (root: `GodotObject`) plus a concrete native wrapper for classes that can be instantiated or returned. Respect `api_type` (`core` → `Godot`, `editor` → `Godot.Editor`).
2. **Constructors**: `X()` for instantiable classes calls `classdb_construct_object2` and binds the wrapper (lifetime handled in phase 07; emit calls to its API).
3. **Methods**: one Julia method per engine method, first arg `self::X` (abstract type, so subclasses and user scripts inherit). Typed args/returns, default values from the API as Julia defaults, varargs for `is_vararg`. Static methods as functions on `Type{X}`: `ResourceLoader.load(...)`-style singleton access and `X.static_method(...)` via `getproperty(::Type{X}, ...)` dispatch or a nested module — document the choice.
4. **Properties**: `Base.getproperty`/`setproperty!` on the abstract type, resolved at compile time from `Symbol` constants (type-stable via `Val`-free `if` chains or generated functions). Also emit explicit getter/setter methods. Indexed properties supported.
5. **Signals**: per class, signal metadata (name, arg types) for phase 10 typed connect/emit helpers.
6. **Enums/bitfields/constants**: class-scoped and global. Enums as a typed integer wrapper with named instances and `show`; bitfields support `|`, `&`, `~`, `in`. Reachable as `Node.ProcessMode.PROCESS_MODE_INHERIT`-like nesting or `Node.PROCESS_MODE_INHERIT` — pick the most ergonomic option, ensure no world-age/type piracy issues, and record it in an ADR.
7. **Singletons**: `Input`, `Engine`, `OS`, ... resolve lazily via `global_get_singleton` and allow `Input.is_action_pressed("jump")`.
8. **Utility functions**: `GD`-equivalent module (`print`, `push_error`, `randf`, `load`, `str_to_var`, ...) avoiding clashes with `Base.print` (C# uses `GD.Print`; expose as `GD.print` and export non-clashing names).
9. **Virtual methods**: emit stub generic functions (`function _process end`) with docstrings, plus a registry mapping virtual names → Julia functions used by phase 08 to detect overrides via `hasmethod`.
10. **Docs**: convert class-reference BBCode (`[method foo]`, `[code]`, `[codeblocks]` — keep the C#/GDScript example as reference) to Markdown docstrings.
11. **Name hygiene**: rename `Object` → `GodotObject`; escape Julia keywords (`function`, `end`, `type`, `global`, ...) with a documented suffix; for names exported by `Base` (e.g. `Timer`), define but do not export. Generate a report of all renames.
12. **Builtin types** (`Vector2`, ...) are *not* generated here — phase 05 hand-writes them; generator only emits glue for builtin methods not covered by the hand-written versions.
13. **Extension classes**: support regenerating against an API dump that includes other GDExtensions' classes (parity with C# seeing extension classes).

## Quality

- Generated code is deterministic, formatted, and loads in < N seconds with precompilation (measure and record).
- `Godot` precompiles cleanly (`PrecompileTools` workload covering common calls).
- Unit tests in `julia/GodotBindgen/test` using a trimmed fixture API JSON.
- Integration test: create a `Node2D`, set `position`, call `get_child_count`, read `Engine.get_version_info()`.

Update parity rows 2.1–2.12.
