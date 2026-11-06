# ADR 0004: Editor API as a separate package loaded only in the editor

- Status: Accepted
- Date: 2026-11-04
- Amends: the `Godot.Editor` bullet of the architecture in `.github/copilot-instructions.md`

## Context

C# ships the editor-only engine API (`EditorPlugin`, `EditorInterface`, ...) in a separate assembly, GodotSharpEditor. `CSharpLanguage` loads it only when `Engine.is_editor_hint()` is true. Exported games never contain or load it.

Phase 04 first generated the 82 editor classes (722 methods) as a submodule `Godot.Editor` compiled into `Godot`. Julia compiles a package into a single cache, so a submodule cannot be loaded on demand. Every game therefore paid to load the editor API, and the phase 14 export would have to ship it.

## Decision

- **Separate package.** The editor API is the package `GodotEditor` (`julia/GodotEditor`, uuid `5b0e7c3a-1d64-4c8e-9f2b-6a7d3e9c41f0`). It depends on `Godot` and includes the generated `src/generated/classes.jl`, which GodotBindgen writes next to the core bindings.
- **Shared generic functions.** Every method generic function, editor-only ones included, stays owned by `Godot`. `GodotEditor` adds methods to them (`Godot.add_tool_menu_item(self::EditorPlugin, ...)`). Virtual stubs (`Godot._get_plugin_name`) stay in `Godot`, so phase 08 overrides use one spelling.
- **Registration.** `GodotEditor.__init__` registers its wrappers, signals and virtuals through `Internals.register_classes!`. That function also clears the class-name → wrapper cache.
- **Loading.** At `MODULE_INITIALIZATION_LEVEL_EDITOR` the native host calls `Godot.Runtime.load_editor_api!()`, but only if `Engine.is_editor_hint()` is true, because editor binaries running a game also reach that level. The call loads `GodotEditor` and binds it as the constant `Godot.Editor`. This is the same condition C# uses.
- **Usage.** Users write `Godot.Editor.EditorPlugin`, or `using GodotEditor` in tool scripts.
- **Missing editor types in core.** If a core API ever references an editor type, the generator degrades it to `GodotObject` in the core scope. In 4.7 no core API references an editor type.

## Consequences

- Warm `using Godot` dropped from 0.59 s to 0.47 s. `GodotEditor` loads in about 0.25 s, only in the editor.
- Phase 14 exports simply omit `julia/GodotEditor`.
- `Godot.Editor` exists only after `load_editor_api!()` runs. Precompiled user packages that need editor types must depend on `GodotEditor` directly, just as C# projects reference GodotSharpEditor only for editor code.
