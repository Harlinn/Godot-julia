---
name: gdjl-11-hot-reload
description: "Phase 11: hot reload of Julia scripts in the editor and running game with state preservation, matching C# assembly reload behavior."
agent: agent
---
Implement script hot reload. Follow the [project instructions](../copilot-instructions.md). Behavioral references: `csharp_script.cpp` (`CSharpLanguage::reload_assemblies`, `_reload_scripts`, `CSharpScript::reload`, state backup/restore of instances and placeholders, `assembly_reload_attempts`), `GodotPlugins/Main.cs` (collectible `AssemblyLoadContext` unload/reload), and `ScriptSerializationGenerator` (`SaveGodotObjectData` / `RestoreGodotObjectData`).

## Requirements

1. **Triggers**: editor file change / save (`_reload_tool_script`, `_reload_all_scripts`, `_reload_scripts`), the "Build" action (phase 12), and live-editing a running game via the remote debugger's script reload.
2. **Generations**: each reload evaluates the script into a new generation module. The old type is retired; instances are migrated to the new type (Julia cannot redefine structs — create new instances of the new type bound to the same native object).
3. **State transfer**: before reload, serialize every live instance's fields (exported and non-exported), per C# rules: values that are Variant-compatible are transferred by Variant, Julia-only values transferred when the field still exists with a compatible type; dropped fields are discarded; new fields get defaults. Signal connections made through Julia callables are restored where the target still exists.
4. **Shared packages**: when user packages (`using MyGameLib`) change, reload them (Revise.jl-based tracking where available, otherwise re-load in a fresh module chain) before reloading dependent scripts. Document limitations versus .NET ALC unloading.
5. **Failure handling**: if a script fails to load, keep instances as placeholders preserving their state and report errors (C# behavior when the build fails); retry up to `julia/project/reload_attempts`.
6. **Tool scripts**: running `@tool` instances in the editor reload in place without losing inspector state.
7. **Memory**: old generations become collectible once no instances reference them; verify no unbounded growth.

## Tests

- Integration: modify a script file during a headless run (driven by the test harness), trigger reload, assert field values preserved and new method behavior active.
- Removing a field / changing its type does not crash.
- Syntax error during reload keeps old state as placeholders; fixing it restores the instances.

Update parity rows 7.1–7.5.
