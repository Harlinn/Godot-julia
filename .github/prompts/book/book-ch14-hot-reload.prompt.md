---
name: book-ch14-hot-reload
description: "Book chapter 14: the logic behind gdjl-11-hot-reload — reloading Julia scripts with state transfer when the language cannot redefine structs."
agent: agent
---
Write chapter 14 of the book, `docs/book/14-hot-reload.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-11-hot-reload](../gdjl-11-hot-reload.prompt.md).

## Focus

- **Stating the language constraint inside the prompt.** "Julia cannot redefine structs — create new instances of the new type bound to the same native object." Giving the agent the key insight up front prevents it from fighting the language.
- **Porting a policy, not just code.** C#'s state backup/restore rules (`SaveGodotObjectData`/`RestoreGodotObjectData`): which fields transfer, which are dropped, and how failures fall back to placeholders with `reload_attempts`.
- **Honest limitations.** "Document limitations versus .NET ALC unloading." Asking the agent to state what cannot be matched.
- **Testing a dynamic feature headlessly.** The harness rewrites a script file during a run and asserts preserved state and new behavior.

## Leads to Verify

- ADR 0011 and `runtime/reload.jl`: all script loads go through `reload_scripts!`. `ScriptInstance.obj`/`info` are mutable with a `suspended` flag, and user code is reached only through `user_method(si, name)`.
- Retiring old generations uses `Base.visit(Core.methodtable)` and `Base.delete_method`; deleted methods remain visible to `visit`.
- Custom callables pin a `JuliaCallable` box so their hash stays stable across reloads. Closure names are stable per function in Julia 1.13.
- The `reload` integration test writes `res://Mover.jl` from `versions/*.jl.txt`.
- Memory: old generations become collectible. Check how this is verified.

## Artifacts to Inspect

`julia/Godot/src/runtime/reload.jl`, `docs/adr/0011-hot-reload.md`, `tests/integration/reload/`.

## Try It Yourself

Run the reload integration test, then ask the agent to add a case where a field changes type, and predict the outcome from the ADR before running it.

Parity rows: 7.1–7.5. Navigation: previous chapter 13, next chapter 15.
