---
name: book-ch07-bindings-generator
description: "Book chapter 7: the logic behind gdjl-04-bindings-generator — generating the whole Godot API for Julia and letting the agent decide (and record) API shape."
agent: agent
---
Write chapter 7 of the book, `docs/book/07-bindings-generator.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-04-bindings-generator](../gdjl-04-bindings-generator.prompt.md).

## Focus

- **Scale through generation.** The generator emits the full engine API from `extension_api.json`. Get the counts from matrix row 2.1. Explain the rule "never hand-edit generated code; change the generator" and why it matters even more when an agent does the editing.
- **Delegated design authority with an obligation.** "Pick the most ergonomic option… and record it in an ADR" (enums, static methods, singletons). Show what ADR 0003 decided (for example `is_action_pressed(Input, x)`, prefixed enum constants such as `Node_PROCESS_MODE_ALWAYS`, the `GD` module) and how ADR 0004 split the editor API into `GodotEditor`.
- **Name hygiene as a requirement.** `Object` → `GodotObject`, keyword escaping, names exported by `Base` defined but not exported, and a generated rename report. The agent produces an audit trail of its own decisions.
- **Testing a generator.** Trimmed fixture JSON for unit tests, plus an integration test against the real engine.

## Leads to Verify

- A bug class caused by name shadowing: inside module `Godot`, generated classes shadow `Base` names. `WeakRef()` constructed a Godot `WeakRef`, which caused infinite recursion in the binding create callback and a stack overflow. Package code must write `Base.WeakRef`, `Base.Timer`, and so on.
- Generator details: emit `local __r` before `try`, `eval`/`include` are reserved names, and `global_enums.jl` must be included before `classes.jl`.
- Precompile time of the generated package (check `docs/perf.md`), and why `PrecompileTools` was replaced by plain `precompile` directives (the engine's isolated `LOAD_PATH`).
- Extension classes: `fetch_api.jl --project=…` dumps an API including other GDExtensions' classes (`api_type` `extension`/`editor_extension`).

## Artifacts to Inspect

`julia/GodotBindgen/src/`, `julia/GodotBindgen/test/`, `scripts/generate_bindings.jl`, `julia/Godot/src/core/gd.jl`, `julia/Godot/src/precompile.jl`, `docs/adr/0003-generated-api-shape.md`, `docs/adr/0004-editor-api-package.md`, `tests/integration/bindings/`. Run the generator only if needed to report current numbers, and say so in the chapter.

## Try It Yourself

Ask the Ask agent to find three entries in the generated rename report (`binding_report.txt`) and explain each rule that produced them. Then ask the Plan agent how it would add a new naming rule end to end (generator, tests, ADR).

Parity rows: 2.1–2.12. Navigation: previous chapter 6, next chapter 8.
