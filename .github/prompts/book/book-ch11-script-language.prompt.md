---
name: book-ch11-script-language
description: "Book chapter 11: the logic behind gdjl-08-script-language — registering Julia as a Godot script language via exhaustive virtual-method checklists."
agent: agent
---
Write chapter 11 of the book, `docs/book/11-script-language.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-08-script-language](../gdjl-08-script-language.prompt.md).

## Focus

- **Exhaustive checklists.** The prompt lists every `ScriptLanguageExtension`/`ScriptExtension` virtual and every script-instance callback. Explain why enumerating the surface beats "implement the interface" (agents otherwise stop at the subset that makes the first test pass).
- **Forward references to later phases** ("phase 11", "phase 12", "phase 13"). The agent stubs the virtuals now and knows who completes them later, so nothing is silently dropped.
- **Thin native shims, logic in Julia.** The architecture rule from the instructions applied concretely: one ABI entry, `script_call(method, self, args, argc, ret)`, forwarding to `Godot.Runtime.BRIDGE`.
- **The script model**: one file = one `@godot_class` named after the file, evaluated into a fresh module per generation (prepares hot reload in phase 11).
- **"Unimplemented virtuals must not be reported to the engine."** A parity detail with a performance effect.

## Leads to Verify

- Godot 4.7 semantics: `Object::get_script()` returns `script_instance->get_script()`, so the script instance must hold a reference to its script (`reference_object` in instance create, unref in free). Otherwise scripts get freed under live nodes.
- `Script.is_valid`/`inherits_script` are not exposed to GDScript, and invalid scripts are not attached to scene nodes. This shaped how the tests were written.
- The bridge `method` argument must be `Ptr{UInt8}`, because `Cstring` has no `unsafe_convert` to `Ptr`.
- Scripts get `const X = script_type(path)` for every Julia global class named in their source (`bind_global_classes!`, added later for the demos).

## Artifacts to Inspect

`native/src/julia_script.h`, `native/src/julia_script.cpp`, `julia/Godot/src/runtime/bridge.jl`, `scripts.jl`, `instances.jl`, `julia/Godot/src/object/scripting.jl`, `docs/adr/0008-script-language.md`, `tests/integration/scripts/`.

## Try It Yourself

Pick one virtual from the prompt's list and ask the agent to show the C++ shim, the Julia handler, and the C# equivalent side by side.

Parity rows: 2.11, 4.3, 4.9, 5.1–5.4, 5.18, 8.6, 8.7. Navigation: previous chapter 10, next chapter 12.
