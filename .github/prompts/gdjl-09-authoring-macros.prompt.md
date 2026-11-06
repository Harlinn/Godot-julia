---
name: gdjl-09-authoring-macros
description: "Phase 9: Julia authoring macros equivalent to C# attributes + source generators (@godot_class, @export*, @signal, @tool, @global_class, @icon, @rpc) with analyzer-style diagnostics."
agent: agent
---
Implement the user-facing script authoring API in `julia/Godot/src/macros/`. Follow the [project instructions](../copilot-instructions.md). Behavioral references: `Godot.SourceGenerators/` (`ScriptPathAttributeGenerator`, `ScriptPropertiesGenerator`, `ScriptPropertyDefValGenerator`, `ScriptMethodsGenerator`, `ScriptSignalsGenerator`, `ScriptSerializationGenerator`, `MustBeVariantAnalyzer`, `GlobalClassAnalyzer`, diagnostic descriptors), `GodotSharp/Core/Attributes/`, and docs `c_sharp_exports.rst`, `c_sharp_signals.rst`, `c_sharp_global_classes.rst`.

Phase 08 already provides the base: `@godot_class` (in `julia/Godot/src/object/scripting.jl`) handles plain `@export`, `@signal`, the `tool`/`global_class`/`abstract`/`icon` options and the `@tool`/`@global_class`/`@icon` wrappers. Body annotations are rewritten syntactically by `@godot_class` and are not standalone macros. Extend that expansion, feeding hints/usage/groups into `Runtime.ScriptField` and `Runtime.property_type`/`field_prop` (ADR 0008), rather than starting over. Add integration tests for the `_get`/`_set`/`_get_property_list`/`_validate_property` overrides (row 5.18, dispatch already implemented in `runtime/instances.jl`).

## Target Syntax (refine, but keep the spirit)

```julia
using Godot

@tool
@global_class
@icon("res://icons/player.svg")
@godot_class mutable struct Player <: CharacterBody2D
    @export_category("Movement")
    @export speed::Float64 = 300.0
    @export_range(0, 100, 1; or_greater = true) health::Int = 100
    @export_group("Visuals", prefix = "visual_")
    @export visual_tint::Color = Color(1, 1, 1)
    @export target::Union{Node2D, Nothing} = nothing
    @export items::GDArray{Item} = GDArray{Item}()
    @export_tool_button("Reset", "Reload") reset_action::Callable = Callable(reset!)
    cooldown::Float64 = 0.0          # not exported, still serialized across hot reload

    @signal health_changed(old::Int, new::Int)
end

@rpc(:any_peer, :call_local, :reliable) function shoot(self::Player, dir::Vector2) ... end

Godot._physics_process(self::Player, delta::Float64) = ...
```

## Requirements

1. **`@godot_class`**: injects the native handle field, generates constructors (engine path + Julia path), field defaults, `getproperty`/`setproperty!` that prefer Julia fields then fall back to inherited Godot properties, and emits a metadata record consumed by `Godot.Runtime` (equivalent to the C# generated `GetGodotPropertyList`, `GetGodotMethodList`, `GetGodotSignalList`, `InvokeGodotClassMethod`, `SetGodotClassPropertyValue`, `GetGodotClassPropertyValue`, `HasGodotClassMethod`). Generated dispatch must be static (no `getfield(obj, sym)` with runtime symbols on hot paths).
2. **Methods exposed to the engine**: every function whose first argument is annotated with the script type and is defined in the script module is exposed (C# exposes all methods of the class). Static methods: functions taking `::Type{Player}`.
3. **Exports**: every C# export form, including all `PropertyHint`s: `@export_range`, `@export_enum`, `@export_flags`, `@export_flags_2d_physics/render/navigation/avoidance` (and 3D), `@export_file`, `@export_dir`, `@export_global_file/dir`, `@export_multiline`, `@export_placeholder`, `@export_exp_easing`, `@export_color_no_alpha`, `@export_node_path`, `@export_storage`, `@export_custom(hint, hint_string, usage)`, Node/Resource-typed exports, typed `GDArray{T}`/`GDDictionary{K,V}`, enums and bitfields (Julia `@enum` and generated Godot enums), groups/subgroups/categories, tool buttons.
4. **Default values**: record initializer expressions per property for `_has_property_default_value`/`_get_property_default_value` (inspector revert arrows).
5. **Signals**: `@signal name(args...)` generates signal metadata, a cached `StringName` (`Player.SignalName.health_changed` equivalent), typed `emit_health_changed(self, old, new)` and typed `connect_health_changed(self, f)` helpers (C# event parity).
6. **Attributes**: `@tool`, `@global_class` (name + base for Create dialog), `@icon(path)`, `@rpc(mode, sync, transfer_mode, channel)` feeding `_get_rpc_config`. Abstract scripts (`@godot_class abstract type ...` or an `abstract=true` flag) supported.
7. **StringName caches**: generated `MethodName`, `PropertyName`, `SignalName` constants per script.
8. **Diagnostics**: macro-expansion-time errors that mirror the C# analyzer diagnostics (e.g. class name ≠ file name, exporting non-Variant-compatible type, exporting a `Node` from a non-`Node` script, signal args not Variant-compatible, `@global_class` on a type not deriving from `GodotObject`, generic script types). Use stable codes `GDJL0001…` mapped to the C# `GD0xxx` codes in a table in `docs/diagnostics.md`.

## Tests

- Unit tests for macro expansion (metadata snapshot tests) and every diagnostic.
- Integration: inspector-visible property list (via `get_property_list()` from GDScript) matches an expected list including hints/usage/groups; default revert values; RPC config dictionary; global class appears in `ProjectSettings.get_global_class_list()`.

Update parity rows 2.10, 3.13, 5.5–5.19.
