# ADR 0000: Deliver Julia support as a GDExtension, not an engine module

- Status: Accepted
- Date: 2026-11-02

## Context

Godot's C# support is an engine module (`modules/mono/`). It requires a separate ".NET" editor build and separate export templates. Its entry point (`modules/mono/register_types.cpp` at `4.7.2-stable`) does only four things at `MODULE_INITIALIZATION_LEVEL_SCENE`:

1. registers the `CSharpScript` class,
2. creates the `GodotSharp` binding singleton,
3. registers `CSharpLanguage` with `ScriptServer`,
4. adds `.cs` `ResourceFormatLoader`/`ResourceFormatSaver`.

GDExtension exposes equivalents of all four (`ClassDB` registration, `Engine.register_script_language` with `ScriptLanguageExtension`/`ScriptExtension`, `ResourceLoader.add_resource_format_loader`, `ResourceSaver.add_resource_format_saver`), plus `script_instance_create3`, placeholder script instances, instance bindings, custom callables, `EditorPlugin`, and `EditorExportPlugin`.

## Decision

Ship Julia support as a GDExtension built with `godot-cpp` that registers a `ScriptLanguageExtension`. It must run on the official, unmodified Godot editor and export templates.

## Consequences

- Users install an addon instead of a special editor build. This improves on C# (row 1.2).
- We depend on the stability of the GDExtension API. We target `api_version=4.7` (`compatibility_minimum = "4.7"`).
- The extension library is marked `reloadable = false`, because the embedded Julia runtime cannot be unloaded. Script hot reload (phase 11) works inside the runtime and does not rely on reloading the library.

### Module-only capabilities to watch

These are the parts of `modules/mono` that use engine internals rather than public APIs. If GDExtension turns out to be insufficient for any of them, the phase that owns it must record a `GAP` with a workaround.

| Capability in `modules/mono` | Internal mechanism | GDExtension route | Phase |
|---|---|---|---|
| Interop function table (`glue/runtime_interop.cpp`) | Direct calls into engine C++ | `gdextension_interface` functions via `get_proc_address` | 03 |
| Script instances (`CSharpInstance`) and refcount hooks | `ScriptInstance` subclass | `GDExtensionScriptInstanceInfo3` (`refcount_incremented/decremented`) | 07, 08 |
| Placeholder instances in the editor | `PlaceHolderScriptInstance` | `placeholder_script_instance_create`/`_update` | 08 |
| Global class discovery during the filesystem scan | `ScriptLanguage::get_global_class_name` | `_get_global_class_name` (extension must be loaded before the scan) | 08, 12 |
| Assembly reload with state backup (`CSharpLanguage::reload_assemblies`) | Iterates every script instance in the engine | Track instances on our side; `_reload_scripts` / `_reload_tool_script` | 11 |
| Build button and MSBuild panel (`GodotTools`) | Editor module plus managed plugin | `EditorPlugin` toolbar/bottom-panel controls | 12 |
| Script debugger stack, errors, and break (`debug_*`) | `ScriptLanguage` virtuals | Same virtuals on `ScriptLanguageExtension` | 13 |
| Per-platform export (`GodotTools/Export/ExportPlugin.cs`) | `EditorExportPlugin` plus mono-specific templates | `EditorExportPlugin` (`add_shared_object`, `_get_export_features`, ...) | 14 |
