# ADR 0011: Script hot reload

- Status: Accepted
- Date: 2026-11-05

## Context

C# reloads by unloading the collectible `AssemblyLoadContext` that holds the project assembly, loading the rebuilt one, and rebuilding every scripted object: state is saved with the generated `SaveGodotObjectData`, delegates with `DelegateUtils.TrySerializeDelegate`, and objects whose script fails become placeholders (`CSharpLanguage::reload_assemblies`). GDScript keeps its instances and remaps their members (`GDScriptLanguage::reload_scripts`). Julia cannot redefine structs or unload code, but each script file already evaluates into a fresh module per load (ADR 0008).

## Decision

- **Triggers.**
  - `JuliaLanguage::_reload_scripts` (remote debugger live edit, editor), `_reload_all_scripts` and `_reload_tool_script` re-read the files, push the source back into the `JuliaScript` resource, and reload.
  - `JuliaScript::_reload` (editor "reload from disk", `set_source_code` + `reload`) reloads from the given source.
  - `JuliaRuntime.reload_scripts(paths)` does what the debugger's `reload_scripts` message does. It is used by the tests and by future "Build" action of phase 12.
  - Reloading unchanged, valid source is a no-op.
- **Dependents.** A load records the scripts it inherits from or references with `script_type`. Reloading a script also reloads every script that depends on it, in dependency order, because their types refer to the old class.
- **Migration in place.** The engine-side script instance is kept; only its Julia struct changes, like GDScript. For each live instance a new-generation struct is built (field initializers run, `_init` does not, as with GDScript's soft reload), then every field that still exists takes its old value:
  - values of the new field type as is;
  - convertible values via `convert`, for example `Int` to `Float64`;
  - enums and structs declared in the script, rebuilt as the same-named type of the new generation;
  - vectors element-wise.
  Removed fields are dropped; incompatible type changes and new fields keep their defaults. Values move directly in memory, not through Variants (C# serializes because the old assembly goes away), so Julia-only values survive. The new struct becomes the object's wrapper; the old one reads as freed.
- **References.** Fields of other live script instances that held a migrated struct are pointed at its replacement, including elements of `Vector` fields. Connected Julia callables (custom Callables pin a `JuliaCallable` box whose hash is fixed at creation, so Godot's connection maps stay valid) are re-targeted:
  - closures and functions of the old generation become the same-named ones of the new generation, with captured instances replaced. Julia 1.13 names closures per enclosing function (`#arm##0#arm##1`), so names are stable across edits that do not reorder closures in a function;
  - closures defined elsewhere keep their code with captured instances replaced (immutable closures rebuilt, mutable callable structs updated, `Core.Box` contents swapped);
  - a callable whose code is gone is disabled with a warning, as C# drops delegates it cannot deserialize.
- **Failure.** If a script (or a script it depends on) fails to load, its instances are *suspended*: their Julia state is kept and stays readable and writable as properties, but no user code runs (no methods, notifications, `_get`/`_set`). This is the role C#'s placeholders play. A later successful reload migrates them. Reloads that failed from disk are retried once per frame, up to the project setting `julia/project/reload_attempts` (default 3, C#: `dotnet/project/assembly_reload_attempts`); unchanged files are not re-evaluated. **Deviation:** `ScriptInstanceExtension` cannot become a `PlaceHolderScriptInstance` (the engine `static_cast`s placeholders), so suspended instances report `is_placeholder() == false`.
- **Retiring generations.** After a reload, generation modules no longer used by a loaded script or a live instance are retired. All their methods are deleted from the global method table (engine virtuals such as `Godot._ready`, `getproperty`, generated helpers), and their class records are dropped. Dispatch tables and runtime registries therefore do not grow with reloads. This is the closest Julia gets to unloading an ALC.
- **Shared packages.** If the user has loaded Revise.jl, `Revise.revise()` runs before scripts are reloaded, so changed package methods take effect. Without Revise, packages are not reloaded.

## Consequences and limitations

- **Compiled code is never freed in Julia.** Retiring removes methods and records, but each reload leaks the old generation's compiled code and type objects (and one call-thunk type per called method). This is small, but it grows with the number of reloads in a session.
- **Tasks keep the old code.** Godot tasks (`godot_task`) suspended in old code resume on deleted methods and fail with a reported `MethodError`. Julia values outside script instances (package globals, `Dict`s) that hold old structs are not updated and see freed objects. C# has the same issue with state outside Godot objects.
- **Package limits.** Struct redefinitions in packages need Revise's own limits or a restart: Julia cannot unload a package the way an ALC unloads assemblies.
- **Cost.** Sweeping the method table costs about 40 ms per reload (55k methods).
