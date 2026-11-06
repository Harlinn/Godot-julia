---
name: gdjl-08-script-language
description: "Phase 8: implement JuliaLanguage/JuliaScript/script instances via ScriptLanguageExtension so .jl files attach to nodes like C# scripts."
agent: agent
---
Register Julia as a Godot script language. Follow the [project instructions](../copilot-instructions.md). Behavioral reference: `modules/mono/csharp_script.h/.cpp` (`CSharpLanguage`, `CSharpScript`, `CSharpInstance`, `PlaceHolderScriptInstance` usage) and `Bridge/ScriptManagerBridge.cs`, `Bridge/CSharpInstanceBridge.cs`. C++ classes in `native/` are thin shims that forward to `Godot.Runtime` in Julia.

## Native Shims (`native/src/`)

1. `JuliaLanguage : ScriptLanguageExtension`, registered with `Engine::register_script_language` and unregistered on deinit. Implement every virtual; for each, match `CSharpLanguage` behavior. Notable ones:
   - `_get_name` = "Julia", `_get_type` = "JuliaScript", `_get_extension` = "jl", `_get_recognized_extensions` = `["jl"]`.
   - `_get_reserved_words`, `_is_control_flow_keyword`, `_get_comment_delimiters` (`#`, `#= =#`), `_get_doc_comment_delimiters`, `_get_string_delimiters` (`"`, `"""`, `` ` ``).
   - `_validate` → parse with `JuliaSyntax` and lower; return errors/warnings with line/column.
   - `_has_named_classes`, `_handles_global_class_type`, `_get_global_class_name` (read `@global_class` without executing the file — parse-only).
   - `_make_template`, `_get_built_in_templates`, `_is_using_templates`, `_preferred_file_name_casing` (PascalCase like C#).
   - `_can_make_function`/`_make_function`/`_find_function` (signal connection dialog inserts handler stubs — C# returns false for make; match or exceed).
   - `_open_in_external_editor`/`_overrides_external_editor` (phase 12), `_debug_*` (phase 13), `_reload_*` (phase 11), `_thread_enter/_thread_exit`, `_frame` (pumps the Julia main-thread scheduler; phase 10).
2. `JuliaScript : ScriptExtension`: implement every virtual (`_can_instantiate`, `_get_instance_base_type`, `_instance_create`, `_placeholder_instance_create`, `_is_tool`, `_is_valid`, `_is_abstract`, `_get_global_name`, `_get_base_script`, `_inherits_script`, `_has_method`, `_has_static_method`, `_get_method_info`, `_get_script_method_list`, `_get_script_property_list`, `_get_script_signal_list`, `_has_script_signal`, `_has_property_default_value`, `_get_property_default_value`, `_update_exports`, `_get_constants`, `_get_members`, `_get_member_line`, `_get_rpc_config`, `_get_documentation`, `_get_class_icon_path`, `_reload`, `_get_source_code`/`_set_source_code`).
3. `ResourceFormatLoaderJulia` / `ResourceFormatSaverJulia` for `.jl`.
4. Script instances via `script_instance_create3` with a full `GDExtensionScriptInstanceInfo3` table whose callbacks dispatch into Julia (`set`, `get`, `get_property_list`, `property_can_revert`, `property_get_revert`, `validate_property`, `get_owner`, `get_property_state`, `get_method_list`, `has_method`, `get_method_argument_count`, `call`, `notification`, `to_string`, `refcount_incremented/decremented`, `is_placeholder`, `get_language`, `free`).
   The Julia struct for an instance becomes the object's wrapper via `Godot.bind_wrapper!` (phase 07, ADR 0007), so engine calls that return the object (`get_parent`, `get_node`, signal arguments) yield the user's struct. `refcount_incremented/decremented` follow the same strong/weak rules as the instance binding.

## Julia Side (`Godot.Runtime`)

1. **Script loading**: evaluate a `.jl` file into a fresh module (`Module(:Script_<hash>_<gen>)`) with `using Godot` pre-imported; locate exactly one `@godot_class` whose name equals the file's base name; extract metadata produced by the phase 09 macros. Report violations as script errors with file:line.
2. **Inheritance**: base type is either a Godot class (abstract type) or another Julia script class (`res://` path) — support script-to-script inheritance like C# class inheritance.
3. **Dispatch**: `call` resolves method name → Julia function once per script generation and caches it; virtual engine callbacks (`_ready`, `_process`, `_physics_process`, `_input`, `_unhandled_input`, `_notification`, `_get`, `_set`, `_get_property_list`, `_validate_property`, `_to_string`, ...) are found by `hasmethod(Godot._ready, Tuple{T})`. Unimplemented virtuals must not be reported to the engine (so Godot skips them, as with C#).
4. **Arguments**: converted from `Variant` per declared Julia argument types; arity/type errors produce Godot call errors (`GDEXTENSION_CALL_ERROR_*`), not crashes.
5. **Placeholders**: in the editor, non-`@tool` scripts get placeholder instances exposing exported properties with defaults.

## Tests

- Attach a `.jl` script to a node in a headless scene: `_ready`, `_process`, `_notification` run; exported property set in `.tscn` is applied.
- GDScript calls a Julia method, reads/writes a Julia property, and connects to a Julia-declared signal.
- Julia script inheriting another Julia script.
- Syntax error in a script reports file:line and does not crash.

Update parity rows 2.11, 4.3, 4.9, 5.1–5.4, 5.18, 8.6, 8.7.
