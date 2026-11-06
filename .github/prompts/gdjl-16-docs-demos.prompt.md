---
name: gdjl-16-docs-demos
description: "Phase 16: user documentation mirroring the Godot C# docs, and Julia ports of the official C# demo projects."
argument-hint: "Optional: specific doc page or demo to produce"
agent: agent
---
Write user documentation and demo ports. Scope: `${input:scope:all docs and demos}`. Follow the [project instructions](../copilot-instructions.md). References: godot-docs `tutorials/scripting/c_sharp/` and the C# projects in `godotengine/godot-demo-projects` (folder `mono/`), plus the "Your first 2D game" tutorial's C# code.

## Documentation (`docs/user/`)

Create one page per C# page, adapted to Julia, with every C# example translated:

| C# page | Julia page |
|---------|------------|
| `c_sharp_basics` | `julia_basics.md` — install, setup, editor config, first script, project structure |
| `c_sharp_features` | `julia_features.md` — type conversion, casting, `get_node(T, …)`, preprocessor/feature-tag equivalents |
| `c_sharp_differences` | `julia_api_differences.md` — naming, renamed types (`GodotObject`, `GDArray`, unexported clashes), `GD` functions, singletons, operators |
| `c_sharp_signals` | `julia_signals.md` |
| `c_sharp_exports` | `julia_exports.md` |
| `c_sharp_global_classes` | `julia_global_classes.md` |
| `c_sharp_variant` | `julia_variant.md` |
| `c_sharp_collections` | `julia_collections.md` |
| `c_sharp_style_guide` | `julia_style_guide.md` |
| (C# async sections) | `julia_async.md` |
| (C# debugging) | `julia_debugging.md` (link phase 13 doc) |
| (C# export notes) | `julia_export.md` |

Also include a "Coming from C#" cheat sheet (side-by-side syntax table) and a "Performance tips" page (type stability, avoiding allocations in `_process`, sysimages).

Every code block must be extracted and executed by a doc test (`scripts/doctest_docs.jl`) inside a headless project.

## Demos (`demos/`)

Port, keeping scene files and assets identical where licensing allows (demos are MIT/CC0 — keep attribution):
1. *Dodge the Creeps* (2D tutorial)
2. 2D platformer or *Pong*
3. A 3D demo (e.g. *Squash the Creeps*)
4. A multiplayer demo using `@rpc`
5. An editor plugin demo using `@tool`

Each demo runs headlessly in CI for a few seconds without errors (integration harness from phase 15).

Update parity rows 11.1–11.2.
