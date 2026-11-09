---
name: book-ch12-authoring-macros
description: "Book chapter 12: the logic behind gdjl-09-authoring-macros — Julia macros as the equivalent of C# attributes, source generators and analyzers."
agent: agent
---
Write chapter 12 of the book, `docs/book/12-authoring-macros.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-09-authoring-macros](../gdjl-09-authoring-macros.prompt.md).

## Focus

- **Prompts evolve with the code.** The second paragraph ("Phase 08 already provides the base… Extend that expansion… rather than starting over") was written after phase 08 had run. Explain how and why to revise downstream prompts once upstream phases have landed, to prevent duplicate or conflicting implementations.
- **Showing the target syntax.** A complete example script with "refine, but keep the spirit". Examples communicate API intent better than prose, and they leave room for language-specific fixes.
- **Mapping concepts across ecosystems.** C# attributes and Roslyn source generators/analyzers map to Julia macros and macro-expansion-time diagnostics. Cover the stable `GDJLnnnn` codes mapped to C# `GD0xxx` in [`docs/diagnostics.md`](../../../docs/diagnostics.md).
- **Static generated dispatch** (no runtime-symbol `getfield` on hot paths) as a performance requirement for metaprogramming.

## Leads to Verify

- `@m(args) decl` is invalid Julia syntax, so annotations use `@m (args) decl`. The prompt's sample syntax had to be adjusted, which is a concrete case of "keep the spirit".
- A field named `export` is a keyword (`spec` is used instead).
- A unit test requires every diagnostic code in the source to appear in `docs/diagnostics.md`. Documentation is enforced by tests.
- Per-class `script_get_field`/`script_set_field!` methods are `Core.eval`'d into `Runtime`.
- Empty comprehensions infer an element type of `Union{}`, so they are typed (`String[...]`) before `push!`.
- Changing `julia/Godot` sources forces recompilation at Godot startup (>60 s). The workflow fix is to precompile before short-timeout integration runs.

## Artifacts to Inspect

`julia/Godot/src/object/scripting.jl` and any `julia/Godot/src/macros/` files, `docs/adr/0009-script-authoring.md`, `docs/diagnostics.md`, the macro and diagnostics unit tests under `julia/Godot/test/`, and the integration tests for property lists, defaults and RPC config.

## Try It Yourself

Ask the agent to add a new diagnostic (for example a misspelled export hint) end to end: code, documented code number, unit test. Then confirm the documentation test fails if the docs entry is removed.

Parity rows: 2.10, 3.13, 5.5–5.19. Navigation: previous chapter 11, next chapter 13.
