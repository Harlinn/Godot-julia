---
name: book-ch19-docs-demos
description: "Book chapter 19: the logic behind gdjl-16-docs-demos — page-for-page user docs with executed code blocks, and Julia ports of the official C# demos."
agent: agent
---
Write chapter 19 of the book, `docs/book/19-docs-demos.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-16-docs-demos](../gdjl-16-docs-demos.prompt.md).

## Focus

- **A mapping table as the spec.** The C# page → Julia page table makes the documentation scope complete and checkable.
- **"Every code block must be extracted and executed by a doc test."** This is the remedy for plausible-looking but wrong AI-written documentation. Explain how `scripts/doctest_docs.jl` works (pages in order, `{no-run}` opt-out, `@godot_class` blocks written to `res://<page>/<Class>.jl`).
- **Demos as end-to-end acceptance tests.** Porting real C# demos (Dodge the Creeps, Pong, Squash the Creeps, multiplayer Pong, an editor plugin) exercises the whole stack and surfaces integration bugs that unit tests miss. Mention concrete bugs found this way, if verifiable.
- **Licensing hygiene with an agent.** Demos stay MIT with attribution (`demos/LICENSE.md`), skip the Apache header, and keep assets unchanged.
- **`${input:scope:…}`.** Splitting large documentation work across sessions.

## Leads to Verify

- `julia demos/run.jl` runs each demo headlessly through `driver.gd` as an autoload via `override.cfg`. Editor plugins ignore `override.cfg`, so the runner patches `project.godot` temporarily (`editor_driver.gd`).
- `scripts/port_csharp_demo.jl` exists. Describe what it automates and what the agent still had to do by hand.
- Findings from the ports: script methods must not return a `Task`, and `bind_global_classes!` was added so scripts can name other global classes.

## Artifacts to Inspect

`docs/user/` (all pages, including `coming_from_csharp.md` and `performance_tips.md`), `scripts/doctest_docs.jl`, `scripts/port_csharp_demo.jl`, `demos/` (README, `run.jl`, `driver.gd`, `editor_driver.gd`, and each demo's `.jl` scripts), `demos/LICENSE.md`.

## Try It Yourself

Put a deliberate mistake in a code block in a `docs/user` page, run the doc test, and let the agent fix it. Then compare one demo's Julia script with the original C# script, side by side.

Parity rows: 11.1–11.2. Navigation: previous chapter 18, next chapter 20.
